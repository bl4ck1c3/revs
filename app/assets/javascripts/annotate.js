anno.addHandler('onAnnotationCreated', function(annotation) {
  annotation.context=annotation.context.split("?")[0]; // if the item page has querystring parameters, this causes the JSON.parse to fail on the server, so just strip them off here
  jQuery.ajax({
    type: "POST",
    url: "/annotations",
    dataType: "JSON",
    data: "annotation="+encodeURIComponent(JSON.stringify(annotation))+"&druid=" + druid() + "&n=" + imageNumber(),
    success: function(data) {
      annotation.id=data.id; // the annotation ID should match the database row ID so we can delete it if needed
      updateAnnotationsPanel(data.num_annotations,druid());
      // these are added so the display to the user is correct for the new annotation; they will be set on the server when the page loads for all annotations
      annotation.username=I18n["me"];
      annotation.updated_at=I18n["today"];
    }
    });
});

anno.addHandler('onAnnotationUpdated', function(annotation) {
  annotation.context=annotation.context.split("?")[0]; // if the item page has querystring parameters, this causes the JSON.parse to fail on the server, so just strip them off here
  jQuery.ajax({
    type: "PUT",
    dataType: "JSON",
    url: "/annotations/" + annotation.id,
    data: "annotation="+encodeURIComponent(JSON.stringify(annotation)),
    success: function(data) {
      updateAnnotationsPanel(data.num_annotations,druid());
    }
  });
});

// this gets called when the user clicks the delete icon
anno.addHandler('beforeAnnotationRemoved', function(annotation) {
  var r=confirm(I18n["delete_annotation"]);
  if (r==false) { return false;}
});

// this is what gets called when the annotation is actually deleted (assuming the user clicks OK to the confirmation dialog)
anno.addHandler('onAnnotationRemoved', function(annotation) {
  jQuery.ajax({
    type: "DELETE",
    dataType: "JSON",
    url: "/annotations/" + annotation.id,
    success: function(data) {
      updateAnnotationsPanel(data.num_annotations,druid());
    }
  });
});

// this plugin allows us to add the username and date to each annotation and display it
annotorious.plugin.addUsernamePlugin = function(opt_config_options) { }
annotorious.plugin.addUsernamePlugin.prototype.onInitAnnotator = function(annotator) {
  // A Field can be an HTML string or a function(annotation) that returns a string
    annotator.popup.addField(function(annotation) {
      if (annotation.username != '') {
        return '<em>' + I18n["from"] + ' ' + annotation.username + ' - '+ annotation.updated_at +'</em>'
      }
    else
     {
       return ''
      }
    });
}
anno.addPlugin('addUsernamePlugin', {});

function updateAnnotationsPanel(num_annotations,druid) {
  $(".num-annotations-badge").text(num_annotations); // update the total annotations badge
  $(".num-annotations-badge").removeClass('hidden');
  $("#all-annotations").load("/annotations/for_image/"+druid);// re-render the annotations panel
  $('#all-annotations').removeClass('hidden-offscreen hidden'); // be sure it is visible
}

function showAnnotations() {
  togglePURLEmbed();
  toggleThumbImage();
  loadAnnotations();
  enableAnnotations();
}

function hideAnnotations() {
  togglePURLEmbed();
  toggleThumbImage();
}

function enableAnnotations() {
  anno.makeAnnotatable(jQuery('#annotatable_image')[0]);
}

function loadAnnotations(image_number) {
  image_number = typeof image_number !== 'undefined' ? image_number : 0;
  jQuery.getJSON("/annotations/for_image/"+druid()+ ".json?image_number="+image_number,function(data) {
    for (var i = 0; i < data.length; i++) {
        annotation = JSON.parse(data[i].json)
        anno.addAnnotation(annotation);
      }
  });
}

function togglePURLEmbed() {
  jQuery('#image_workspace').toggleClass('hidden');
}

function toggleThumbImage() {
  jQuery('#annotatable_workspace').toggleClass('hidden');
}

function disableNewAnnotations() {
  try{anno.setSelectionEnabled(false);}
  catch(err) {}
}

function toggleLinks() {
  $('.annotation_links').toggleClass('hidden-offscreen');
  $('#hide_annotations_link').toggleClass('hidden-offscreen');
}

// Added if/else conditions below during Bootstrap 3 upgrade because BS 3 prevents
// JQuery from toggling the .hide and .show classes during animations as expected:
// https://github.com/twbs/bootstrap/issues/9237
// They might fix in Bootstrap 4; if so, it might be that
// only the slideToggle line is needed.
function toggleAnnotationList(){
  if ($('#all-annotations').hasClass('hidden')) {
    $('#all-annotations').removeClass('hidden').hide().slideToggle('slow');
  } else {
    $('#all-annotations').slideToggle('slow');
  }
}

function reEnableAnnotations() {
  $("#annotatable_image").load(function() {
    loadAnnotations(imageNumber());
    enableAnnotations();
    }
  );
}

$(document).ready(function(){

  $(document).on( "click","#previous_annotatable_image",function() {
    $("#annotatable_workspace").load("/annotations/show_image_number/" + druid() + "?image_number=" + parseInt(imageNumber()-1),function() {reEnableAnnotations();}
    );
  });
  
  $(document).on( "click","#next_annotatable_image",function() {
    $("#annotatable_workspace").load("/annotations/show_image_number/" + druid() + "?image_number=" + parseInt(imageNumber()+1),function() {reEnableAnnotations();}
    );
  }); 
      
  $(document).on('mouseleave','.annotation-info',function(){anno.highlightAnnotation();});
  $(document).on('mouseenter','.annotation-info',function(){
    annotation=($(this).data('json'));
    if (imageNumber() != annotation.image_number) {  // if we are not currently showing the image with this annotation, switch to it
      $("#annotatable_workspace").load("/annotations/show_image_number/" + druid() + "?image_number=" + annotation.image_number,function() {
        loadAnnotations(annotation.image_number);
        enableAnnotations();
        anno.highlightAnnotation(annotation); 
      });
      }
    else
    {
      anno.highlightAnnotation(annotation);   
    }
  });
    
  $('#annotate_link').click(function() {
    showAnnotations();
    toggleLinks();
    toggleAnnotationList();
    return false;
   });

  $('#view_annotations_link').click(function() {
     showAnnotations();
     disableNewAnnotations();
     toggleLinks();
     toggleAnnotationList();
     return false;
   });

  $('#hide_annotations_link').click(function() {
     hideAnnotations();
     toggleLinks();
     toggleAnnotationList();
     return false;
   });

});
