class PagesController < ApplicationController  
  def home
  end
  
  def css_test
  end
  
  def kaboom
    User.first.kaboom!
  end

#{ie6_method if ie6_blocking == 'light'}  
end
