ActionMailer::Base.smtp_settings = {
  :address => "#{smtp_address}",
  :port => 25,
  :domain => "#{smtp_domain}",
  :authentication => :login,
  :user_name => "#{smtp_username}",
  :password => "#{smtp_password}"  
}

# base64 encodings - useful for manual SMTP testing:
# username => #{base64_user_name}
# password => #{base64_password}