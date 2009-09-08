class AccountsController < InheritedResources::Base
  actions :new, :show, :edit, :update
  respond_to :html
  defaults :resource_class => User, :instance_name => 'user'
  
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update]
  
  new! do |format|
    format.html { render :template => "users/new" }
  end

  #{account_create_block}
  
  show! do |format|
    format.html { render :template => "users/show" }
  end

  edit! do |format|
    format.html { render :template => "users/edit" }
  end
  
  update! do |success, failure|
    failure.html { render :template => "users/edit" }
  end

protected
  def resource
    @user ||= @current_user
  end
end
