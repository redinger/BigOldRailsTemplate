class PagesController < ApplicationController
  
  def home
    @page_title = '#{current_app_name}'
  end
  
  def css_test
    @page_title = "CSS Test"
  end
  
  def kaboom
    User.first.kaboom!
  end

#{ie6_method if ie6_blocking == 'light'}  
end
