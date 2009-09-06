class Notifier < ActionMailer::Base
  default_url_options[:host] = "#{default_url_options_host}"
  
  def password_reset_instructions(user)
    setup(user)
    subject "Password Reset Instructions"
    body :edit_password_reset_url => edit_password_reset_url(user.perishable_token)
  end

  def welcome_email(user)
    setup(user)
    subject "Welcome to #{current_app_name}!"
    body :user => user
  end
  
  #{activation_instructions_block}
private

  def setup(user)
    from "#{notifier_email_from}"
    sent_on Time.now
    recipients user.email
  end
  
end
