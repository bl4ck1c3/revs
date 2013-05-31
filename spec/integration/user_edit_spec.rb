require 'spec_helper'

describe("Editing of logged in users",:type=>:request,:integration=>true) do

  before :each do
    logout
  end
    
  it "should allow a logged in user to update their profile" do
   
    new_bio='I am super cool.'
    new_last_name='Rockin'
    
    login_as(user_login)
    user_account=User.find_by_username(user_login)
    visit user_profile_name_path(user_account.username)
    page.should have_content("#{user_account.full_name}'s Profile")
    click_link 'Edit your profile'

    fill_in 'user_bio', :with=>new_bio
    fill_in 'user_last_name', :with=>new_last_name
    click_button 'submit'
    
    current_path.should == user_profile_name_path(user_account.username)
    page.should have_content(new_bio)
    page.should have_content(new_last_name)
    
    # check database
    user_account=User.find_by_username(user_login)
    user_account.bio.should == new_bio
    user_account.last_name.should == new_last_name
    
  end

  it "should allow a logged in user to update their password" do
   
    new_password='new_password'
    
    login_as(user_login)
    user_account=User.find_by_username(user_login)
    
    visit user_profile_name_path(user_account.username)
    page.should have_content("#{user_account.full_name}'s Profile")
    click_link 'Edit your account info'

    fill_in 'user_password', :with=>new_password
    fill_in 'user_password_confirmation', :with=>new_password
    fill_in 'user_current_password', :with=>login_pw

    click_button 'submit'
    
    current_path.should == user_profile_name_path(user_account.username)

    # now try and login again with old password, this should fail
    logout
    login_as(user_login)
    current_path.should == new_user_session_path
    page.should have_content('Your account was not found or your password was incorrect.')
    
    # login with new password, this should succeed
    visit new_user_session_path
    fill_in "user_login", :with => user_login
    fill_in "user_password", :with => new_password
    click_button "submit"
    visit user_profile_name_path(user_account.username)
    page.should have_content("#{user_account.full_name}'s Profile")
    
  end

  it "should allow a sunet user to login and edit their profile but should not let them edit their email or password" do

    new_bio='I work at Stanford. That makes me smart.'
    new_last_name='Professor'
    
    visit webauth_login_path
    sunet_account=User.find_by_username(sunet_login)
    
    visit user_profile_name_path(sunet_account.username) # user profile page
    page.should have_content sunet_account.full_name
    page.should_not have_content 'Edit your account info' # we shouldn't have the edit account info link
    
    click_link 'Edit your profile'

    fill_in 'user_bio', :with=>new_bio
    fill_in 'user_last_name', :with=>new_last_name
    click_button 'submit'
    
    current_path.should == user_profile_name_path(sunet_account.username)
    page.should have_content(new_bio)
    page.should have_content(new_last_name)
    
    # check database
    user_account=User.find_by_username(sunet_login)
    user_account.bio.should == new_bio
    user_account.last_name.should == new_last_name   
     
    # confirm we can't get to the edit password/email page via the URL either
    visit edit_user_account_path
    current_path.should == root_path
    page.should have_content 'You are not authorized to perform this action.'
    
    # sign out
    visit user_profile_name_path(sunet_account.username) # user profile page
    logout
    current_path.should == root_path
    page.should_not have_content sunet_account.full_name
    
  end

end