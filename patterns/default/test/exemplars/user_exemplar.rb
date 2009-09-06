class User < ActiveRecord::Base
  generator_for :login, :method => :next_login
  generator_for :password => 'bobby'
  generator_for :password_confirmation => 'bobby'
  generator_for :email, :method => :next_email
  
  def self.next_login
    @last_login ||= 'bobby'
    @last_login.succ!
  end
  
  def self.next_email
    @base ||= 'BobDobbs'
    @base.succ!
    "#{@base}@example.com"
  end
  
end
