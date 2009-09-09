# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  
  # Block method that creates an area of the view that
  # is only rendered if the request is coming from an
  # anonymous user.
  def anonymous_only(&block)
    if !logged_in?
      block.call
    end
  end
  
  # Block method that creates an area of the view that
  # only renders if the request is coming from an
  # authenticated user.
  def authenticated_only(&block)
    if logged_in?
      block.call
    end
  end
  
  # Block method that creates an area of the view that
  # only renders if the request is coming from an
  # administrative user.
  def admin_only(&block)
    role_only("admin", &block)
  end

  def state_options
    I18n.t('states').collect{|abbrev, full_name| [full_name.to_s, abbrev.to_s]}.sort{|a,b| a.first <=> b.first}
  end

  def state_options_with_blank(label = "")
    state_options.unshift([label, ""])
  end

  def full_state_name(state_abbrev)
    state_options.each do |full_name, abbrev|
      return full_name if abbrev == state_abbrev
    end
    nil
  end

private

  def role_only(rolename, &block)
    if not current_user.blank? and current_user.has_role?(rolename)
      block.call
    end
  end
  
end
