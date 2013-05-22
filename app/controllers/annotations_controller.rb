require 'json'

class AnnotationsController < ApplicationController

  authorize_resource
    
  def show
    
    @annotations=Annotation.includes(:user).where(:druid=>params[:id])
    @annotations.each do |annotation| # loop through all annotations
      annotation_hash=JSON.parse(annotation.json) # parse the annotation json into a ruby object
      annotation_hash[:editable]=can? :update, annotation 
      annotation_hash[:username]=(user_signed_in? && (annotation.user_id==current_user.id) ? "me" : annotation.user.to_s) # add the username (or "me" if current user)
      annotation_hash[:updated_at]=show_as_date(annotation.updated_at)
      annotation_hash[:id]=annotation.id
      annotation.json=annotation_hash.to_json # convert back to json
    end
    
    respond_to do |format|
      format.xml  { render :xml => @annotations.to_xml }
      format.json { render :json=> @annotations.to_json }
    end
    
  end
  
  def create
    
    annotation_json=params[:annotation]
    annotation_hash=JSON.parse(annotation_json)
    @annotation=Annotation.create(:json=>annotation_json,:text=>annotation_hash['text'],:druid=>params[:druid],:user_id=>current_user.id)

    respond_to do |format|
      format.xml  { render :xml => @annotation.to_xml }
      format.json { render :json=> @annotation.to_json }
    end
    
  end
  
  def update 
  
    annotation_json=params[:annotation]
    annotation_hash=JSON.parse(annotation_json)
    
    @annotation=Annotation.find(params[:id])
    @annotation.json=annotation_json
    @annotation.text=annotation_hash['text']
    @annotation.save

    respond_to do |format|
      format.xml  { render :xml => @annotation.to_xml }
      format.json { render :json=> @annotation.to_json }
    end
           
  end
  
end