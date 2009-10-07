# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  # Provide access to overrides for restful methods (ie #create! #edit!)
  # See inherited_resources docs for more info.
  include InheritedResources::DSL
  
  helper :all # include all helpers, all the time
  
  # make methods available to views
  helper_method :logged_in?, :admin_logged_in?, :current_user_session, :current_user
  
  # See ActionController::RequestForgeryProtection for details
  protect_from_forgery
  
  # See ActionController::Base for details 
  # Uncomment this to filter the contents of submitted sensitive data parameters
  # from your application log (in this case, all fields with names like "password"). 
  filter_parameter_logging :password, :confirm_password, :password_confirmation, :creditcard
  
  def logged_in?
    !current_user_session.nil?
  end
  
  def admin_required
    unless current_user && current_user.admin?
      flash[:error] = t("flash.require_admin")
      redirect_to root_url and return false
    end
  end
  
  def admin_logged_in?
    logged_in? && current_user.admin?
  end

private
  def current_user_session
    return @current_user_session if defined?(@current_user_session)
    @current_user_session = UserSession.find
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = current_user_session && current_user_session.user
  end

  def require_user
    unless current_user
      store_location
      flash[:notice] = t('flash.require_user')
      redirect_to new_user_session_url
      return false
    end
  end

  def require_no_user
    if current_user
      store_location
      flash[:notice] = t('flash.require_no_user')
      redirect_to account_url
      return false
    end
  end
  
  def store_location
    session[:return_to] = request.request_uri
  end
  
  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end
end
