class Gallery < ActiveRecord::Base
  
  belongs_to :user
  extend FriendlyId
  friendly_id :title, :use => [:slugged]

  include RankedModel
  ranks :row_order,:column => :position

  GALLERY_TYPES=%w{favorites user}
  VISIBILITY_TYPES=%w{public private curator}

  attr_accessible :user_id,:title,:description,:gallery_type,:views,:visibility
  
  has_many :all_saved_items, :class_name=>'SavedItem', :dependent=>:destroy

  validate :check_gallery_type
  validate :check_visibility

  validates :title, :presence=>true
  validates :user_id, :numericality => { :only_integer => true }
  validate :only_one_favorites_list_per_user

  def self.featured
    self.where(:featured=>true).where(:visibility=>'public').order('position ASC,created_at DESC')
  end
  
  def public
    visibility.to_sym == :public
  end

  def image(user=nil)
    item=saved_items(user).limit(1)
    item.size == 0 ? 'default-thumbnail.png' : item.first.solr_document.images.first
  end

  # custom has_many association, so we can add visibility filtering -- get the galleries items, pass in a second user (like the logged in user) to decide if hidden items should be returned as well
  def saved_items(user=nil)
    User.visibility_filter(SavedItem.where(:gallery_id=>id),'saved_items',user).order("position ASC")
  end

  def only_one_favorites_list_per_user
    errors.add(:gallery_type, :cannot_be_more_than_one_favorites_list_per_user) if gallery_type.to_s == 'favorites' && self.class.where(:user_id=>self.user_id,:gallery_type=>:favorites).size != 0
  end
  
  def check_gallery_type
    errors.add(:gallery_type, :not_valid) unless GALLERY_TYPES.include? gallery_type.to_s
  end

  def check_visibility
    errors.add(:visibility, :must_be_selected) unless VISIBILITY_TYPES.include? visibility.to_s
  end 

end
