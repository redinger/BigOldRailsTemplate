class PasswordResetsController < ApplicationController
  before_filter :load_user_using_perishable_token, :only => [:edit, :update]
  
  def new
  end
  
  def create
    @user = User.find_by_email(params[:email])
    if @user
      @user.deliver_password_reset_instructions!
      flash[:notice] = t('flash.password_resets.create.notice')
      redirect_to root_url
    else
      flash[:error] = t('flash.password_resets.create.error')
      render :action => :new
    end
  end
  
  def edit
  end

  def update
    @user.password = params[:user][:password]
    @user.password_confirmation = params[:user][:password_confirmation]
    if @user.save
      flash[:notice] = t('flash.password_resets.update.notice')
      redirect_to account_url
    else
      render :action => :edit
    end
  end

private
  def load_user_using_perishable_token
    @user = User.find_using_perishable_token(params[:id])
    unless @user
      flash[:error] = t('flash.require_user_token')
      redirect_to root_url
    end
  end
end
