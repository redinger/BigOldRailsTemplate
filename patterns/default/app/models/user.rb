class User < ActiveRecord::Base
  acts_as_authentic do |c|
    c.merge_validates_format_of_login_field_options :allow_blank => true
    c.merge_validates_format_of_email_field_options :allow_blank => true, :unless => "email && email.size < 6"
    c.merge_validates_confirmation_of_password_field_options :allow_blank => true
    c.merge_validates_length_of_password_confirmation_field_options :if => "false"
    
    # Put any authlogic customizations here; see the authlogic help
  end
  
  serialize :roles, Array
  
  before_validation_on_create :make_default_roles
  after_create :send_welcome_email
  
  attr_accessible :login, :password, :password_confirmation, :email, :first_name, :last_name
  
  def deliver_password_reset_instructions!
    reset_perishable_token!
    Notifier.deliver_password_reset_instructions(self)
  end
  
  def admin?
    has_role?("admin")
  end
  
  def has_role?(role)
    roles.include?(role)
  end
     
  def add_role(role)
    self.roles << role
  end
     
  def remove_role(role)
    self.roles.delete(role)
  end
  
  def clear_roles
    self.roles = []
  end
  
  def kaboom!
    r = RegExp.new("foo")
  end

private
  def make_default_roles
    clear_roles if roles.nil?
  end
  
  def send_welcome_email
    Notifier.deliver_welcome_email(self)
  end
end
