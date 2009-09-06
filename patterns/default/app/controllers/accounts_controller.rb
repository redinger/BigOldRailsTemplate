class AccountsController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update]
  
  def new
    @user = User.new
    @page_title = "Create Account"
    render :template => "users/new"
  end

  #{account_create_block}
  
  def show
    find_user
    @page_title = "\#{@user.login} details"
    render :template => "users/show"
  end

  def edit
    find_user
    @page_title = "Edit \#{@user.login}"
    render :template => "users/edit"
  end
  
  def update
    find_user
    if @user.update_attributes(params[:user])
      flash[:notice] = "Account updated!"
      redirect_to account_url
    else
      render :template => "users/edit"
    end
  end

private

  def find_user
    @user = @current_user
  end
  
end
