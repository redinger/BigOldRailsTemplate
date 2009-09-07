class PasswordResetsController < ApplicationController
  before_filter :load_user_using_perishable_token, :only => [:edit, :update]
  
  def new
  end
  
  def create
    @user = User.find_by_email(params[:email])
    if @user
      @user.deliver_password_reset_instructions!
      flash[:notice] = t('flash.password_instructions_sent')
      redirect_to root_url
    else
      flash[:notice] = t('flash.email_not_found')
      render :action => :new
    end
  end
  
  def edit
  end

  def update
    @user.password = params[:user][:password]
    @user.password_confirmation = params[:user][:password_confirmation]
    if @user.save
      flash[:notice] = t('flash.password_update_success')
      redirect_to account_url
    else
      render :action => :edit
    end
  end

  private
    def load_user_using_perishable_token
      @user = User.find_using_perishable_token(params[:id])
      unless @user
        flash[:notice] = t('flash.user_token_not_found')
        redirect_to root_url
      end
    end
end
