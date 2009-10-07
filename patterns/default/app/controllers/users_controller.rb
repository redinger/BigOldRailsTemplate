class UsersController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update]
  before_filter :admin_required, :only => [:index, :destroy, :impersonate]
  
  def index
    @users = User.all
  end
  
  def new
    @user = User.new
  end
  
  #{user_create_block}
  
  def show
    find_user
  end

  def edit
    find_user
  end
  
  def update
    find_user
    if @user.update_attributes(params[:user])
      flash[:notice] = t('flash.users.update.notice')
      redirect_to account_url
    else
      render :action => :edit
    end
  end

  def destroy
    find_user
    @user.destroy
    flash[:notice] = t('flash.users.destroy.notice')
    redirect_to(users_url)  
  end

  def impersonate
    find_user
    if @user
      UserSession.create(@user)
      flash[:success] = t('flash.users.impersonate.success', :name => @user.display_name)
    end
    redirect_back_or_default root_url
  end
  
private

  def find_user
    if @current_user.admin? && params[:id]
      @user = User.find(params[:id])
    else
      @user = @current_user
    end
  end
  
end
