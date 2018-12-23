class SessionsController < ApplicationController

  def new
    redirect_to customer_path(current_user) and return if logged_in?
    @page_title = "Login or Create Account"
    if (@gCheckoutInProgress)
      @cart = find_cart
      @display_guest_checkout = allow_guest_checkout?
    end
    @remember_me = true
    @email ||= params[:email]
  end

  def new_from_secret
    redirect_after_login(current_user) and return if logged_in?
  end

  def create
    create_session do |params|
      u = Customer.authenticate(params[:email], params[:password])
      if u.nil? || !u.errors.empty?
        flash.now[:alert] = t('login.login_failed', :username => params[:email])
        flash.now[:alert] << t('login.failed_reason', :why => u.errors.as_html) if u
        Rails.logger.warn "Failed login for '#{params[:email]}' from #{request.remote_ip} at #{Time.current.utc}: #{flash[:alert]}"
        @email = params[:email]
        @remember_me = params[:remember_me]
        render :action => :new
      else
        u.update_attribute(:last_login,Time.current)
        session[:guest_checkout] = false
      end
      u
    end
  end

  def create_from_secret
    create_session do |params|
    # If customer logged in using this mechanism, force them to change password.
      u = Customer.authenticate_from_secret_question(params[:email], params[:secret_question], params[:answer])
      if u.nil? || !u.errors.empty?
        note_failed_signin(u)
        if u.errors.include?(:no_secret_question)
          redirect_to login_path
        else
          redirect_to new_from_secret_session_path
        end
      else
        u.update_attribute(:last_login,Time.current)
        session[:guest_checkout] = false
      end
      u
    end
  end

  def destroy
    logout_killing_session!
    reset_shopping
    redirect_to login_path, :notice => "You have been logged out."
  end

  def temporarily_disable_admin
    session[:admin_disabled] = true
    redirect_to :back, :notice => "Switched to non-admin user view."
  end

  def reenable_admin
    if session.delete(:admin_disabled)
      flash[:notice] = "Admin view reestablished."
    end
    redirect_to :back
  end
  

end
