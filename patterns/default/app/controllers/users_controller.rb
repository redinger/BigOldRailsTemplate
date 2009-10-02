class UsersController < InheritedResources::Base
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update]
  before_filter :admin_required, :only => [:index, :destroy]
  
#{user_create_block}

  update! do |success, failure|
    success.html { redirect_to account_url }
    failure.html { render :action => :edit }
  end

  def impersonate
    @user = User.find(params[:id])
    if @user
      UserSession.create(@user)
      flash[:success] = t('flash.users.impersonate.success', :name => @user.display_name)
    end
    redirect_back_or_default root_url
  end
  
private
  def resource
    @user ||= if(@current_user.admin? && params[:id])
      User.find(params[:id])
    else
      @current_user
    end    
  end
end
