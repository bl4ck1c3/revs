require "rails_helper"

describe("Favorites",:type=>:request,:integration=>true) do

  before :each do
    logout
    @save_favorites_button=I18n.t('revs.favorites.save_to_favorites')
    @remove_favorites_button=I18n.t('revs.favorites.remove_from_favorites',:list_type=>'favorites')
    @druid1='qk978vx9753'
    @druid2='dd482qk0417'
    @Next = "Next"
    @Previous = "Previous"
    @add_new_description=I18n.t('revs.favorites.you_can_add_a_note_html', :item_type=>'favorite',:href=>'add a note')
    @add_new_description_link= I18n.t('revs.favorites.you_can_add_a_note_linktext')
  end

  it "should not show save/remove favorites link for non-logged in users" do
    visit catalog_path(@druid1)
    should_not_have_button(@save_favorites_button)
    should_not_have_button(@remove_favorites_button)
  end

  it "should show save favorites link for a logged in user and allow them to add a favorite" do

    user=get_user(user_login)
    login_as(user_login)
    visit catalog_path(@druid1)
    should_have_button(@save_favorites_button)
    should_not_have_button(@remove_favorites_button)

    # check database to be sure there are no favorites for this user
    expect(user.favorites.size).to eq(0)

    click_button(@save_favorites_button) # save the favorite

    should_not_have_button(@save_favorites_button) # button switches to remove
    should_have_button(@remove_favorites_button)

    expect(user.favorites.where(:druid=>@druid1).size).to eq(1) # favorite is now saved
    expect(user.favorites.reload.size).to eq(1) # user now has one favorite

    # druid2 is not a favorite yet
    visit catalog_path(@druid2)
    should_have_button(@save_favorites_button)
    should_not_have_button(@remove_favorites_button)
    click_button(@save_favorites_button) # save it!

    expect(user.favorites.where(:druid=>@druid2).size).to eq(1) # favorite is now saved
    expect(user.favorites.reload.size).to eq(2) # user now has two favorites

    click_button(@remove_favorites_button) # get rid of the favorite

    should_have_button(@save_favorites_button) # button switches back to add
    should_not_have_button(@remove_favorites_button)

    # favorite is gone
    expect(user.favorites.where(:druid=>@druid2).size).to eq(0) # favorite is now gone
    expect(user.favorites.reload.size).to eq(1) # user now has one favorite
  end

  it "should not show any favorites on a user's profile page if they don't have any favorites" do

    login_as(user_login)
    visit user_path(user_login)
    expect(page).to have_content I18n.t('revs.favorites.you_can_save_favorites')
    visit user_favorites_user_index_path(user_login)
    expect(page).to have_content I18n.t('revs.favorites.none')

  end

  it "should show favorites on a user's profile page if they have favorites and full favorites page should show all of them, including hidden ones since this is a curator" do
    login_as(curator_login)
    visit user_path(curator_login)
    expect(page).not_to have_content I18n.t('revs.favorites.you_can_save_favorites')
    expect(page).to have_content "#{I18n.t('revs.favorites.head')} 4"
    expect(page).to have_content "1 #{I18n.t('revs.favorites.singular')} not shown"
    visit user_favorites_user_index_path(curator_login)
    expect(page).to have_content "Bryar 250 Trans-American:10" # this one is hidden, but shows up for curators
    expect(page).to have_content "A Somewhat Shorter Than Average Title"
    expect(page).to have_content "Thompson Raceway, May 1 -- AND A long title can..."
    expect(page).to have_content "Marlboro 12 Hour, August 12-14"
  end

   it "should not show hidden favorites to a non-logged in user on a public user's profile page if they are hidden" do
    visit user_path(curator_login)
    expect(page).not_to have_content I18n.t('revs.favorites.you_can_save_favorites')
    expect(page).to have_content "#{I18n.t('revs.favorites.head')} 3"
    visit user_favorites_user_index_path(curator_login)
    expect(page).not_to have_content "Bryar 250 Trans-American:10" # this one is hidden, and does not show up for non logged in users
    expect(page).to have_content "A Somewhat Shorter Than Average Title"
    expect(page).to have_content "Thompson Raceway, May 1 -- AND A long title can..."
    expect(page).to have_content "Marlboro 12 Hour, August 12-14"
  end

   it "should not show hidden favorites to a logged in user on their own profile page if they are not curators/admins" do
    login_as(user2_login)
    visit user_path(user2_login)
    expect(page).not_to have_content I18n.t('revs.favorites.you_can_save_favorites')
    expect(page).to have_content "#{I18n.t('revs.favorites.head')} 1"
    visit user_favorites_user_index_path(user2_login)
    expect(page).to have_content "Lime Rock Continental, September 1"
    expect(page).not_to have_content "Bryar 250 Trans-American:10" # this one is hidden, and does not show up for non logged in users
  end

  it "should allow a user to see a list of his favorites that paginates and allow the user to move between pages" do

    original_default_per_page=Revs::Application.config.num_default_per_page
    Revs::Application.config.num_default_per_page=5 # make it a smaller number to facilitate paging test

    description = "This is a decription "
    login_as(user_login)

    #Get a two page list of druids
    fav_druids = (item_druids-default_hidden_druids).first(Revs::Application.config.num_default_per_page*2)
    fav_druids.each do |druid|
      visit catalog_path(druid)
      click_button(@save_favorites_button)
    end
    #Check Out Pagination
    visit user_favorites_user_index_path(user_login)
    expect(page).to have_content @Next
    expect(page).to have_content @Previous

    #Make Sure We Go To the Second Page
    click_link(@Next)

    expect(page).to have_content @Next
    expect(page).to have_content @Previous

    Revs::Application.config.num_default_per_page=original_default_per_page
  end


  it "should allow a user to edit a favorite when viewing all their favorites" do
      new_description="Hello, I am a new description for a favorite."

      login_as(user_login)
      visit catalog_path(@druid2)
      click_button(@save_favorites_button)
      visit user_favorites_user_index_path(user_login)
      expect(page).to have_content get_title_from_druid(@druid2)
      expect(page).to have_content @add_new_description
      expect(page).to have_no_content new_description
      click_link(@add_new_description_link)
      expect(page).to have_content I18n.t('revs.nav.update')
      fill_in('saved_item_description', :with => new_description)
      click_button(I18n.t('revs.nav.update'))
      expect(page).to have_content I18n.t('revs.favorites.edit_item_note')

      #Go check databse to make sure this was updated
      user = get_user(user_login)
      expect(user.favorites[0].description).to eq(new_description)

      #Go back to the favorites page and ensure the new description is still there
      logout
      login_as(user_login)
      visit user_favorites_user_index_path(user_login)
      expect(page).to have_content new_description
      expect(page).to have_content get_title_from_druid(@druid2)
  end

  it "should allow a user to remove a favorite when viewing all their favorites" do
    login_as(user_login)
    user = get_user(user_login)
    expect(user.favorites.size).to eq(0)
    visit catalog_path(@druid2)
    click_button(@save_favorites_button)
    user = get_user(user_login)
    expect(user.favorites.size).to eq(1)
    visit user_favorites_user_index_path(user_login)
    expect(page).to have_content get_title_from_druid(@druid2)
    click_button(@remove_favorites_button)
    user = get_user(user_login)
    expect(user.favorites.size).to eq(0)
    logout
    login_as(user_login)
    visit user_favorites_user_index_path(user_login)
    expect(page).to have_no_content get_title_from_druid(@druid2)
    expect(page).to have_content I18n.t('revs.favorites.none')
  end

   it "should not allow a curator to add a hidden item to their favorites or gallery" do
    hidden_druid=default_hidden_druids.first
    login_as(curator_login)
    visit catalog_path(hidden_druid)
    expect(page).to have_no_content @save_favorites_button
    expect(page).to have_no_content I18n.t('revs.user_galleries.add_to_gallery')
    should_not_have_button("Add") # add to gallery button
  end

  it "should automatically create the default favorites list if it does not exist for an existing user when they login" do
    beta_user=get_user(beta_login)
    expect(beta_user.favorites_list).to be_nil # doesn't exist yet
    login_as(beta_login)
    beta_user=get_user(beta_login)
    expect(beta_user.favorites_list).not_to be_nil # created it
    expect(beta_user.favorites_list.class).to eq(Gallery)
  end

end
