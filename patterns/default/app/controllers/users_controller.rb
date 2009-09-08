class UsersController < InheritedResources::Base
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update]
  before_filter :admin_required, :only => [:index, :destroy]
  
  #{user_create_block}

private
  def resource
    @user ||= if(@current_user.admin? && params[:id])
      User.find(params[:id])
    else
      @current_user
    end    
  end
end
