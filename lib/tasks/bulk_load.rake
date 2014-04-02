# encoding: UTF-8

require 'jettywrapper' unless Rails.env.production? 
require 'rest_client'
require 'csv'
require 'countries'
require 'pathname'
require 'revs-utils'

namespace :revs do
  @sourceid = 'sourceid'
  @seperator = '|'
  @filename = 'filename'
  @csv_extension_wild = '*.csv'
  @csv_extension = ".csv"
  @log_extension = ".out" #use something beside .log to avoid the autorotate feature for .log files
  @success = "SUCCESS:"
  @failure = "FAILURE:"
  @assigner = "="
  @mvf = "_mvf"
  @max_expected_collection_size = 2147483647
  @id = "id"
  
  desc "Find all objects with missing image"
  #Run Me: rake revs:missing_images["John Dugdale Collection"] to just show items
  #Run Me: rake revs:missing_images["John Dugdale Collection","delete] to delete from solr index
  task :missing_images, [:collection_name,:delete] => :environment do |t, args| 
    num_missing=0
    q="collection_ssim:\"#{args[:collection_name]}\""
    @all_docs = Blacklight.solr.select(:params => {:q => q, :rows=>'100000'})
    puts "#{@all_docs['response']['numFound']} documents match search and #{@all_docs['response']['docs'].size} returned"
    @all_docs['response']['docs'].each do |doc|
      item=SolrDocument.new(doc)
      if item.is_item? && (item.images.nil? || item.images.size != 1)
        puts "#{item.id}  ---   #{item.identifier}" 
        if !args[:delete].nil? && args[:delete]="delete"
          url="#{Blacklight.solr.options[:url]}/update?commit=true"
          params="<delete><query>id:#{item.id}</query></delete>"
          puts "DELETING!"
          RestClient.post url, params,:content_type => :xml, :accept=>:xml
        end
        num_missing += 1
      end
    end
    puts "#{@all_docs['response']['docs'].size} scanned; #{num_missing} are missing an image"
  end
  
  desc "Go back and touch every SolrDocument so that it will update the year field to use the sortable year field, remove the UUID from previous pass.."
  #Run Me: rake revs:touch_all["UUID"]
  task :touch_all, [:uuid] => :environment do |t, args|
    #Have Editstore ignore updates by this rake task
    Revs::Application.config.use_editstore = false
    log = Logger.new("#{Rails.root}/log/#{Time.now.to_i}.touch_all#{@log_extension}")
    log.info("Starting touch all, removing UUID: #{args[:uuid]} in production notes.")
    
    #Get all collections
    total_success_count = 0
    total_error_count = 0 
    SolrDocument.all_collections.each do |collection|
      collection_success_count = 0 
      collection_error_count = 0 
      clean_title = RevsUtils.clean_collection_name(collection.title)
      #changes = [[:production_notes, args[:uuid], true]]
      changes = [[:production_notes, args[:uuid],true]]  #Append a new UUID to ensure there is a save
     
      #For each collection, touch every member
      collection.get_members(:include_hidden=>true, :rows=> @max_expected_collection_size).each do |doc|
        druid = doc.id
        doc_changes = changes.dup 
        doc_changes << [:single_year,doc.years.first] if doc.years.size == 1 # set the single year field if there is only one year in the multi-years field
        result_a = update_multi_fields(doc, doc_changes)        
        
        prod_notes = join_content(doc, :production_notes, "") #make an empty call to get the current content
        slice = true
        while slice do
           slice = prod_notes.slice! args[:uuid] #Remove the UUID, multiple times if needed
        end
        doc = SolrDocument.find(druid)
        result_b = update_multi_fields(doc, [[:production_notes, prod_notes]])  #Slice off the UUID and save again
        
        if result_a and result_b
          collection_success_count += 1
        else
          collection_error_count += 1
          log.error("Failed to save: #{druid}") 
        end
        
      end  
      #Record Collection Stats
      total_success_count += collection_success_count
      total_error_count += collection_error_count
      col_druid = collection[@id]
      if collection_error_count == 0
        log.info("#{@success} for collection #{col_druid}, touched #{collection_success_count} with no errors.")
      else
        log.info("#{@failure} for collection #{col_druid}, #{collection_error_count} errors and #{collection_success_count} touched successfully.  #{collection_error_count+collection_success_count} total touches attempted for collection.")
      end
      
    end
    
    if total_error_count == 0
      log.info("#{@success} Run complete with #{total_success_count} touched with no errors.")
    else
      log.info("#{@failure} run complete with #{total_error_count} errors and #{total_success_count} touched successfully.  #{total_error_count+total_success_count} total touches attempted on this run.")
    end
      
  end
  
  
  desc "When passed the location of .csv file(s) and a list of headers, this will generate csv with just those fields, plus fields to find the solr document"
  #Run me: rake revs:bulk_load["SHEETS_LOCATION", header1|header2|etc, output_name] RAILS_ENV=production
  task :csv_for_fields, [:csv_files, :fields, :fn] => :environment do |t, args|
    always_present = [@sourceid, @filename]
    additional_headers = args[:fields].split(@seperator) 
    all_fields = always_present + additional_headers
    files = load_csv_files_from_directory(args[:csv_files])
    full_output_path = "#{Rails.root}/lib/assets/#{args[:fn]}#{@csv_extension}"
    
    #Start Logging
    log = Logger.new("#{Rails.root}/log/#{Time.now.to_i}.csv_for_fields#{@log_extension}")
    log.level = Logger::INFO
    log.info("Starting run with the command line args of csv_fields: #{args[:csv_files]} fields: #{args[:fields]} output filename: #{args[:fn]}")
    
    #Setup the output csv
      CSV.open(full_output_path, "wb") do |csv|
        #Write Out The Headers
        csv << all_fields
        
        #Load each sheet we are taking data from
          files.each do |file|
             data = RevsUtils.read_csv_with_headers(file)
             #Make sure the always there files are present
               always_present.each do |header|
                 log.warn("File #{file} lacks required header: #{header}") if data[0].keys.include?(header) == false
               end
               data.each do |row|
                 out_array = []
                   all_fields.each do |field|
                     out_array.append(row[field])
                     log.warn("Nil value for #{field}, a required field, in #{file}") if row[field] == nil and always_present.include?(field)  
                   end
                 csv << out_array   
               end
      
          end
       end  
  end

  
  
  desc "Load all changes to the metadata from CSV files located in TBD"
  #Run me: rake revs:bulk_load["SHEETS_LOCATION"] RAILS_ENV=production
  task :bulk_load, [:change_files_loc, :local_testing] => :environment do |t, args|
    local_testing = args[:local_testing] || false #Assume we are not testing locally unless told so
    debug_source_id = '2012-027NADI-1967-b1_1.0_0008'
    change_file_location = args[:change_files_loc]
    change_file_extension = @csv_extension_wild
    sourceid = @sourceid
    location = "location"
    format = "format"
    marque = "marque"
    filename = @filename
    year = "date"
    full_date = "full_date"
    seperator =  @seperator
    assigner = @assigner
    multi = @mvf
    model = 'model'
    model_year = 'model_year'
    collection_name = "collection_name"
    collection_names = "collection_names"
    ignore_fields = [sourceid, location, filename, collection_name]  
    location_fields = ['country', 'city', 'state']
    additional_fields = location_fields + [full_date]#add other arrays here if we do anymore splitting
    comma = ","
    comma_splits = [marque, model]
    file_ext = ".tif"
   
  
    #Map the csv names to the field names from 
    csv_to_solr = {'label' => 'title',   
                   model  => 'vehicle_model',
                   year => 'years',
                   format => 'formats',
                   collection_name => collection_names, 
                   'inst_notes' => 'institutional_notes',
                   'prod_notes' => 'production_notes'
                  }
                  
    solr_keys = []
    multi_values = []
    SolrDocument.field_mappings.keys.each do |key|
      solr_keys.append(key.to_s)
      multi_values.append(key.to_s) if SolrDocument.field_mappings[key][:multi_valued]
    end
   
   #These should be the field name from /app/models/solr_document.rb
   multi_values = ['vehicle_model', 'years', "formats", "model_year", "marque", "people"]
  
   #All the CSV headers we know how to handle
   known_headers = csv_to_solr.keys + ignore_fields + solr_keys
    
   #Get a list of all the files we need to process and loop over them
   change_files = load_csv_files_from_directory(change_file_location)
  
   #Setup a master log
   master_log = Logger.new("#{Rails.root}/log/#{Time.now.to_i}.revs_bulk_load#{@log_extension}")
   sleep 1 #This way the log timestamp will be at least oen second ahead of the next log we make and the master log ends up at the top of the list
     
    #Process Each File 
    change_files.each do |file| 
      error_count = 0
      name = Pathname.new(file).basename.to_s
      name.slice! @csv_extension
      log = Logger.new("#{Rails.root}/log/#{Time.now.to_i}.#{name}#{@log_extension}")
      master_log.info("#{file} started at #{Time.now}")
      
      log.level = Logger::ERROR
      
      #Load in the CSV, with the top row being taken as the header
      changes = RevsUtils.read_csv_with_headers(file)
      
      #Ensure we can handle all headers we've found
      bad_header = false 
      changes[0].keys.each do |header|
        if not known_headers.include?(header.strip.downcase)
          bad_header = true
          log.error("In document #{file} the #{header} is an unsupported header")
          master_log.error("#{@failure}#{file} contains unsupported header(s)")
        end
      end
      
      if not bad_header
        changes.each do |row|
          #Get the Solr Document and set it for updating 
          
        
          #DEBUG AREA
          save_id = row[sourceid] if local_testing
          row[sourceid] = debug_source_id if local_testing
        
          #Attempt to get the target based on the source_id
          #target = Blacklight.solr.select(:params =>{:q=>'source_id_ssi:"'+ row['sourceid']+'"'})["response"]["docs"][0]
          target = find_doc_via_blacklight(row[@sourceid])
          
      
          
          #If we can't get the target based on source_id, try it with the filename
          if(target == nil and row[filename] != nil)
            alt_attempt = row[filename]
            alt_attempt.slice! file_ext
            target = find_doc_via_blacklight(alt_attempt)
            #target = Blacklight.solr.select(:params =>{:q=>'source_id_ssi:"'+ alt_attempt+'"'})["response"]["docs"][0]
          end
          
       
          #Catch sourceid with no matching druid
          if target == nil
            log.error("In document #{file} no druid found for #{row[sourceid]}") 
            error_count += 1
          end 
          
          if target != nil #Begin Altering Single Solr Document
             doc = SolrDocument.new(target)
           
             #If we have comma splits, replace them with the expected seperator 
             comma_splits.each do |key|
               row[key] = row[key].strip.gsub(comma, seperator) if row[key] != nil
             end
           
           
             #Check to see if we have a format row and clean it up
             
             #Assume there is no change to the format field and we should ignore this key
             ignore_fields.insert(0, format) if not ignore_fields.include?(format)
             
             if row[format] != nil
               current_format = target[SolrDocument.field_mappings[:formats][:field]]
               current_format = current_format.sort if current_format != nil
               format_changes = RevsUtils.revs_check_format(row[format].strip.downcase.split(seperator)).sort
               
               #We have changes 
               if current_format != format_changes
                  row[format] = format_changes.join(seperator)
                  ignore_fields.delete(format) #Pull it out of the ignore fields since we need to make changes here. 
                else
               end
               
             end

             #Check to see if we have a location and see if we need to parse it.
             row = RevsUtils.parse_location(row, location) if row[location] != nil
           
             #Check to see if we need need to handle marques
             if row[marque] != nil 
               array_marque = row[marque].split(seperator)
               count = 0 
               array_marque.each do |m|
                 result = RevsUtils.revs_lookup_marque(m)
                 array_marque[count] = result['value'] if result
                 count += 1
               end
               row[marque] = array_marque.join(seperator)
               #puts row[marque]
             end 
           
             #We could have a full date, a year, or a span of years, handle that.
             if row[year] != nil
               is_full_date = RevsUtils.get_full_date(row[year])
               if is_full_date
                 row[full_date] = row[year]
                 row[year] = nil if year != full_date
               else
                 row[csv_to_solr[year] || year ] = RevsUtils.parse_years(row[year]).join(seperator)
                 row[year] = nil if(csv_to_solr[year] != nil and csv_to_solr[year] != year) #Clear whatever the csv used for year/date if it is not the proper Solr key
               end
             end
             
             #Handle multiple model_years
             if row[model_year] != nil
               row[model_year] = RevsUtils.parse_years(row[model_year]).join(seperator)
             end
           
           
             (changes[0].keys+additional_fields-ignore_fields).each do |key|
               key = key.strip.downcase
               #First make sure we have a real change
               if row[key] != nil
                 #See if the solr document calls the key something else
                   if csv_to_solr[key] != nil
                     proper_key_name = csv_to_solr[key.strip]
                   else
                     proper_key_name = key
                   end   
           
                   #Set up multivalue and send it the value 
                   args = assigner 
                   args = multi+assigner if multi_values.include?(proper_key_name) 
               
                   begin 
                        doc.send(proper_key_name+args, row[key].strip)
                        #puts "Sending: #{proper_key_name+args} #{row[key].strip}" 
                   rescue
                       log.error("In document #{file} on row #{row[sourceid]}, failed to send the key: #{proper_key_name+args} and value: #{row[key]}")
                   end 
               end
             end
           
             success = doc.save
             
             log.error("In document #{file} save error for #{save_id} "+" #{changes[0].keys-ignore_fields+additional_fields} #{row}") if(not success and local_testing)
             log.error("In document #{file} save error for #{row[sourceid]}") if(not success and not local_testing)
             error_count  += 1 if not success 
           
           end #End Altering Single Solr Document   
          
        end
        master_log.info("#{@success}#{file} had no errors.") if error_count == 0
        master_log.error("#{@failure}#{file} had #{error_count} error(s).") if error_count != 0
        puts file if local_testing
        puts error_count if local_testing
      end
      
    
    end 
  end
  
  desc "Cleanup formats in solr documents by removing extra spaces in specific format fields"
  task :cleanup_formats => :environment do
    Revs::Application.config.use_editstore = false

    formats_to_cleanup=["black-and-white film ","black-and-white negatives/color negatives "]

    formats_to_cleanup.each do |format_to_cleanup|
      results=Blacklight.solr.select(:params => {:fq=>'format_ssim:"' + format_to_cleanup + '"',:rows=>'200000'})
      puts "Found #{results['response']['docs'].size} documents with '#{format_to_cleanup}'"
      results['response']['docs'].each do |result|
        doc=SolrDocument.new(result)
        doc.update_solr('format_ssim','update',[format_to_cleanup.strip])
        puts "Updating #{doc.id}"
      end
    end

  end

  desc "Cleanup marques in solr documents by removing 'automobile'"
  task :cleanup_marques => :environment do
    Revs::Application.config.use_editstore = false

    results=Blacklight.solr.select(:params => {:q=>'automobiles OR automobile',:rows=>'200000'})
    puts "Found #{results['response']['docs'].size} documents with the term automobile"
    results['response']['docs'].each do |result|
      doc=SolrDocument.new(result)
      marques=doc.marque
      if marques.class == Array 
        doc.update_solr('marque_ssim','update',marques.map{|marque| RevsUtils.clean_marque_name(marque)})
      end
      puts "Updating #{doc.id}"
    end

  end

  desc "Move flags to favorites for a user, run with rake revs:move_flags_to_favs['jsummer5@stanford.edu']"
  task :move_flags_to_favs, [:username] => :environment do |t, args|
      username=args[:username]  # jsummer5@stanford.edu
      user=User.where(:username=>username).limit(1).first
      if user.nil?
        puts "#{username} not found"
      else
        flags=user.flags
        if flags.size == 0 
          puts "#{username} has no flags"          
        else
          puts "Moving #{flags.size} flags for #{username} to favorites"
          flags.each do |flag|
            existing_fav=user.favorites.where(:druid=>flag.druid)
            if existing_fav.size == 0 # favorite doesn't exist yet, so add it
              favorite=SavedItem.save_favorite(:user_id=>user.id,:description=>flag.comment,:druid=>flag.druid)
              if favorite.id != nil 
                flag.destroy
                puts "Favorite added for #{flag.druid}; flag removed"
              else
                puts "Favorite could not be added for #{flag.druid}; flag NOT removed"
              end
            else
              puts "favorite already exists for #{flag.druid}; flag NOT removed"
            end
        end
      end
    end
  end
  
  class RevsUtils    
    extend Revs::Utils
    include Revs::Utils
  end
    
  def load_csv_files_from_directory(file_location)
    return Dir.glob(File.join(file_location, @csv_extension_wild))
  end

  def find_doc_via_blacklight(source)
     return Blacklight.solr.select(:params =>{:q=>'source_id_ssi:"'+ source+'"'})["response"]["docs"][0]
  end
  
  #Note, this function doesn't save the document, I just return a content string!
  def join_content(doc, field, content)
    current_content = doc[SolrDocument.field_mappings[field][:field]]  
    return content if current_content == nil
    current_content = current_content.join(@seperator) if SolrDocument.field_mappings[field][:multi_valued] 
    current_content = current_content + content
    return current_content
  end
  
  def get_args_for_send(field)
    args = @assigner  
    args = @mvf + args if SolrDocument.field_mappings[field][:multi_valued]
    return args
  end
  
  
  #Note you will need to refetch the document to see the changes after calling this function
  def update_multi_fields(doc, changes)
    #Fields is expected to be in the form of [[field, content, append]]
    #Ex: [[:title, "My New Title"],[:people, "Person I Forgot To List", true]]
    changes.each do |change|
      content = change[1]
      content = join_content(doc, change[0], change[1]) if change[2]
      doc.send(change[0].to_s+get_args_for_send(change[0]),content)
    end
    return doc.save #Returns true if this all worked
  end


end