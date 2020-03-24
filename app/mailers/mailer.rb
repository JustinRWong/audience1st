class Mailer < ActionMailer::Base

  helper :customers, :application, :options

  # the default :from needs to be wrapped in a callable because the dereferencing of Option may
  #  cause an error at class-loading time.
  default :from => Proc.new { "AutoConfirm@#{Option.sendgrid_domain}" }

  before_action :set_delivery_options

  def email_test(destination_address)
    @time = Time.current
    mail(:to => destination_address, :subject => 'Testing')
  end
  
  def confirm_account_change(customer, whathappened, token=nil, requestURL=nil)
    @whathappened = whathappened
    if requestURL
      uri = URI(requestURL)
      @token_link = reset_token_customers_url(:token => token, :host => uri.host, :protocol => uri.scheme)
    end
    @customer = customer
    mail(:to => customer.email, :subject => "#{@subject} #{customer.full_name}'s account")
  end

  def confirm_order(purchaser,order)
    @order = order
    # show-specific notes
    @notes = @order.collect_notes.join("\n\n")
    mail(:to => purchaser.email, :subject => "#{@subject} order confirmation")
  end

  def confirm_reservation(customer,showdate,vouchers)
    @customer = customer
    @showdate = showdate
    @seats = Voucher.seats_for(vouchers)
    @notes = @showdate.patron_notes if @showdate
    mail(:to => customer.email, :subject => "#{@subject} reservation confirmation")
  end

  def cancel_reservation(old_customer, old_showdate, seats)
    @showdate,@customer = old_showdate, old_customer
    @seats = seats
    mail(:to => @customer.email, :subject => "#{@subject} CANCELLED reservation")
  end

  def donation_ack(customer,amount,nonprofit=true)
    @customer,@amount,@nonprofit = customer, amount, nonprofit
    @donation_chair = Option.donation_ack_from
    mail(:to => @customer.email, :subject => "#{@subject} Thank you for your donation!")
  end
   
  def general_mailer(template_name, params, subject)
    params.keys.each do |key|
      self.instance_variable_set("@#{key}", params[key])
    end
    @subject << subject 
    mail(:to => params[:recipient],
             :subject => @subject, 
             :template_name => template_name)        
  end
  protected

  def set_delivery_options
    @venue = Option.venue
    @subject = "#{@venue} - "
    @contact = if Option.help_email.blank?
               then "call #{Option.boxoffice_telephone}"
               else "email #{Option.help_email} or call #{Option.boxoffice_telephone}"
               end
    if Rails.env.production? and Option.sendgrid_domain.blank?
      ActionMailer::Base.perform_deliveries = false
      Rails.logger.info "NOT sending email"
    else
      ActionMailer::Base.perform_deliveries = true
      ActionMailer::Base.smtp_settings = {
        :user_name => 'apikey',
        :password => Figaro.env.SENDGRID_KEY,
        :domain   => Option.sendgrid_domain,
        :address  => 'smtp.sendgrid.net',
        :port     => 587,
        :enable_starttls_auto => true,
        :authentication => :plain
      }
      # use Sendgrid's "category" tag to identify which venue sent this email
      headers['X-SMTPAPI'] = {'category' => "#{Option.venue} <#{Option.sendgrid_domain}>"}.to_json
    end
  end
end
