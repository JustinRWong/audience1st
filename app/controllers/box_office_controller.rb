class BoxOfficeController < ApplicationController

  before_filter(:is_boxoffice_filter,
                :redirect_to => { :controller => :customers, :action => :login})

  # sets the instance variable @showdate for every method.
  before_filter :get_showdate
  verify(:method => :post,
         :only => :do_walkup_sale,
         :redirect_to => { :action => :walkup },
         :add_to_flash => "Warning: action only callable as POST, no transactions were recorded! ")

  ssl_required(:walkup, :do_walkup_sale)   if RAILS_ENV == 'production'

  private

  # this filter must return non-nil for any method on this controller
  def get_showdate
    return true if (!params[:id].blank?) &&
      (@showdate = Showdate.find_by_id(params[:id].to_i))
    if (showdate = (Showdate.current_or_next ||
                    Showdate.find(:first, :order => "thedate DESC")))
      redirect_to :action => action_name, :id => showdate
    else
      flash[:notice] = "There are no shows listed.  Please add some."
      redirect_to :controller => 'shows', :action => 'index'
    end
  end

  public

  def index
    redirect_to :action => :walkup
  end

  def change_showdate
    unless ((sd = params[:id].to_i) &&
            (showdate = Showdate.find_by_id(sd)))
      flash[:notice] = "Invalid show date."
    end
    redirect_to :action => :walkup, :id => sd
  end

  def door_list
    perf_vouchers = @showdate.vouchers
    unless perf_vouchers.empty?
      @total = perf_vouchers.size
      @num_subscribers = perf_vouchers.select { |v| v.customer.is_subscriber? }.size
      @vouchers = perf_vouchers.group_by do |v|
        "#{v.customer.last_name},#{v.customer.first_name},#{v.customer_id},#{v.vouchertype_id}"
      end
      render :layout => false
    else
      flash[:notice] = "No reservations for '#{@showdate.printable_name}'"
      redirect_to :action => 'walkup', :id => @showdate
    end
  end

  def walkup
    @vouchertypes = Vouchertype.walkup_vouchertypes
    @showdates = Showdate.all_shows_this_season
    @showdate = Showdate.find_by_id(params[:id]) || Showdate.current_or_next
  end

  def do_walkup_sale
    if params[:commit].match(/report/i) # generate report
      redirect_to(:controller => 'report', :action => 'walkup_sales',
                  :showdate_id => @showdate)
      return
    end
    qtys = params[:qty]
    # CAUTION: disable_with on a Submit button makes its name (params[:commit])
    # empty on submit!
    is_cc_purch = !(params[:commit] && params[:commit] != APP_CONFIG[:cc_purch])
    vouchers = []
    # recompute the price
    total = 0.0
    ntix = 0
    begin
      qtys.each_pair do |vtype,q|
        ntix += (nq = q.to_i)
        total += nq * Vouchertype.find(vtype).price
        nq.times  { vouchers << Voucher.anonymous_voucher_for(@showdate, vtype) }
      end
      total += (donation=params[:donation].to_f)
    rescue Exception => e
      flash[:checkout_error] = "There was a problem verifying the total amount of the order:<br/>#{e.message}"
      redirect_to :action => :walkup, :id => @showdate
      return
    end
    # link record as a walkup customer
    customer = Customer.walkup_customer
    if is_cc_purch
      if false
        cc = CreditCard.new(params[:credit_card])
        # BUG: workaround bug in xmlbase.rb where to_int (nonexistent) is
        # called rather than to_i to convert month and year to ints.
        cc.month = cc.month.to_i
        cc.year = cc.year.to_i
        # run cc transaction....
        resp = do_cc_present_transaction(total,cc)
        unless resp.success?
          flash[:checkout_error] = "PAYMENT GATEWAY ERROR: " + resp.message
          redirect_to :action => 'walkup', :id => @showdate
          return
        end
        tid = resp.params['transaction_id']
        flash[:notice] = "Transaction approved (#{tid})<br/>"
      end
      tid = 0
      howpurchased = Purchasemethod.get_type_by_name('box_cc')
      flash[:notice] = "Credit card purchase recorded, "
    else
      tid = 0
      howpurchased = Purchasemethod.get_type_by_name('box_cash')
      flash[:notice] = "Cash purchase recorded, "
    end
    #
    # add tickets to "walkup customer"'s account
    # TBD CONSOLIDATE this with 'place_order' code for normal orders
    #
    unless (vouchers.empty?)
      vouchers.each do |v|
        if v.kind_of?(Voucher)
          v.purchasemethod_id = howpurchased
        end
      end
      customer.add_items(vouchers, logged_in_id, howpurchased, tid)
      customer.save!              # actually, probably unnecessary
      flash[:notice] << sprintf("%d tickets sold,", ntix)
      Txn.add_audit_record(:txn_type => 'tkt_purch',
                           :customer_id => customer.id,
                           :comments => 'walkup',
                           :purchasemethod_id => howpurchased,
                           :logged_in_id => logged_in_id)
    end
    if donation > 0.0
      begin
        Donation.walkup_donation(donation,logged_in_id)
        flash[:notice] << sprintf(" $%.02f donation processed,", donation)
      rescue Exception => e
        flash[:checkout_error] << "Donation could NOT be recorded: #{e.message}"
      end
    end
    flash[:notice] << sprintf(" total $%.02f",  total)
    flash[:notice] << sprintf("<br/>%d seats remaining for this performance",
                              Showdate.find(@showdate).total_seats_left)
    redirect_to :action => 'walkup', :id => @showdate
  end

  # AJAX handler called when credit card is swiped thru USB reader
  def process_swipe
    swipe_data = String.new(params[:swipe_data])
    key = session[:otp].to_s
    no_encrypt = (swipe_data[0] == 37)
    if swipe_data && !(swipe_data.empty?)
      swipe_data = encrypt_with(swipe_data, key) unless no_encrypt
      @credit_card = convert_swipe_to_cc_info(swipe_data.chomp)
      @credit_card.number = encrypt_with(@credit_card.number, key) unless no_encrypt
      render :partial => 'credit_card', :locals => {'name_needed'=>true}
    end
  end

end