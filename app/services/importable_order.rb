# This class captures the abstraction of "an order that is almost ready to be imported,
# once we ascertain which customer should get it".  Each instance has an associated +Order+
# object whose +processed_by+ is set to the special customer "box office daemon", and whose
# payment method is set to "sold by external vendor".  Each instance has an associated
# list of +Customer+ objects (which may be empty) of the candidate Customers to which the
# order *could* be assigned based on name/email/etc. matching from an imported will-call list
# or sales list.
#
# Ultimately, the underlying +Order+'s +purchaser+ and +customer+ will both be
# set to the receiving customer (the caller will create a new customer if none are suggested),
# and the order's +external_key+ will be set to the vendor's order ID or order number.
#
# A +TicketSalesImportParser+ should do the following for each order.  Every step that calls
#   an instance method on +ImportableOrder+ may raise +ImportableOrder::MissingDataError+.
#   1. Create a new +ImportableOrder+ for it
#   2. Call +#find_or_set_external_key+ with the vendor's order number
#   3. If the above call results in the +action+ attribute set to +ALREADY_IMPORTED+, we're done
#   4. Otherwise call +#find_valid_voucher_for+ with the performance date as a +Time+, the
#      vendor name as a string (to help find the +ValidVoucher+), and price per ticket as float.
#   5. If a +ValidVoucher+ is returned, call +Order#add_tickets+ on the +ImportableOrder+'s
#      associated +Order+ passing that +ValidVoucher+ and the number of seats of that type.
#   6. Call +#set_possible_customers+ to determine who the order might be imported to.
#   7. Set +description+ to something human-friendly shown in the import view.
#   8. Add this +ImportableOrder+ to an array.
# When all orders in a will-call file have been processed as above, return the array of
# +ImportableOrder+ objects.

class ImportableOrder

  class MissingDataError < StandardError ;  end

  attr_accessor :order
  # +transaction_date+: when the vendor processed the transaction.  When the order is imported,
  # will become the +sold_on+ date for the final +Order+ object.
  attr_accessor :transaction_date
  # +import_first_name,import_last_name+: first and last name as given in the import list
  attr_accessor :import_first_name, :import_last_name
  # +customer_email_in_import+: if given, the email address from import list
  attr_accessor :import_email
  # +customers+: a collection of candidate Customer records to import to
  attr_accessor :customers
  # +action+: ALREADY_IMPORTED, MAY_CREATE_NEW_CUSTOMER, MUST_USE_EXISTING_CUSTOMER
  # 2..n-2=import to selected customer
  attr_reader :action
  # +description+: summary of what will be imported/added
  attr_accessor :description

  ALREADY_IMPORTED =      "ALREADY_IMPORTED"
  MAY_CREATE_NEW_CUSTOMER =   "MAY_CREATE_NEW_CUSTOMER"
  MUST_USE_EXISTING_CUSTOMER = "MUST_USE_EXISTING_CUSTOMER"
  
  def initialize                # :nodoc:
    @order = Order.new(
      :processed_by => Customer.boxoffice_daemon,
      :purchasemethod => Purchasemethod.get_type_by_name('ext'))
    @customers = []
    @action = MAY_CREATE_NEW_CUSTOMER
    @comment = nil
  end

  def find_or_set_external_key(key)
    if (o = Order.completed.find_by(:external_key => key)) # this order has already been imported
      @action = ALREADY_IMPORTED
      @order = o
      @import_first_name = @order.customer.first_name
      @import_last_name = @order.customer.last_name
      @import_email = @order.customer.email
      @transaction_date = @order.sold_on
      @description = @order.summary("<br/>").html_safe
    else
      @order.external_key = key
    end
  end

  def set_possible_customers
    if (!import_email.blank?  && (c = Customer.find_by_email(import_email)))
      # unique match
      @customers = [c]
      @action = MUST_USE_EXISTING_CUSTOMER
    else
      @customers = Customer.possible_matches(import_first_name,import_last_name,import_email)
      @action = MAY_CREATE_NEW_CUSTOMER
    end
  end

  def find_valid_voucher_for(thedate,vendor,price)
    showdate = Showdate.where(:thedate => thedate).first
    price = price.to_f
    raise MissingDataError.new(I18n.translate('import.showdate_not_found', :date => thedate.to_formatted_s(:showtime_including_year))) if showdate.nil?
    vouchertype = Vouchertype.where("name LIKE ?", "%#{vendor}%").find_by(:season => showdate.season, :price => price)
    raise MissingDataError.new(I18n.translate('import.vouchertype_not_found',
        :season => ApplicationController.helpers.humanize_season(showdate.season),
        :vendor => vendor, :price => sprintf('%.02f', price))) if vouchertype.nil?
    redemption = ValidVoucher.find_by(:vouchertype => vouchertype, :showdate => showdate)
    raise MissingDataError.new(I18n.translate('import.redemption_not_found',
        :vouchertype => vouchertype.name,:performance => showdate.printable_name)) if redemption.nil?
    redemption
  end

end
