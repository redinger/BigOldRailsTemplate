require File.join(File.dirname(__FILE__), '..', 'test_helper')

class UserCanLoginTest < ActionController::IntegrationTest

  context 'an existing user' do
    setup do
#{make_user_block}
    end
    
    should 'be able to login with valid id and password' do
      visit login_path
      
      fill_in 'Login', :with => @user.login
      fill_in 'Password', :with => @user.password

      click_button 'Login'

      assert_equal '/', path
      assert_contain "Login successful!"
    end
  end
end
