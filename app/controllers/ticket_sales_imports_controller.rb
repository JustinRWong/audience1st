class TicketSalesImportsController < ApplicationController

  before_filter :is_boxoffice_filter

  # View all imports, also provides a form to create a new import by uploading a file.
  # The view provides a dropdown populated from TicketSalesImporter::IMPORTERS, which
  # should be used to set the 'vendor' field of the import.
  def index
    @ticket_sales_imports = TicketSalesImport.all.sorted
    @vendors = TicketSalesImport::IMPORTERS
  end

  # upload: grab uploaded data, create a new TicketSalesImport instance whose 'vendor'
  # field is populated from the dropdown on the index page and whose 'raw_data' is populated
  # from the contents of the uploaded file

  def create
    @import = TicketSalesImport.new(
      :vendor => params[:vendor], :raw_data => params[:file].read,:processed_by => current_user,
      :existing_customers => 0, :new_customers => 0, :tickets_sold => 0)
    if @import.valid?
      @import.save!
      redirect_to edit_ticket_sales_import_path(@import)
    else
      redirect_to ticket_sales_imports_path, :alert => @import.errors.as_html
    end
  end

  def edit
    @import = TicketSalesImport.find params[:id]
    @import.parse
    redirect_to(ticket_sales_imports_path, :alert => @import.errors.as_html) if !@import.errors.empty?
  end

  # Finalize the import according to dropdown menu selections
  def update
    import = TicketSalesImport.find params[:id]
    order_hash = params[:o]
    # each hash key is the id of a saved (but not finalized) order
    # each hash value is {:action => a, :customer_id => c, :first => f, :last => l, :email => e}
    #  if action is ALREADY_IMPORTED, do nothing
    #  if action is MAY_CREATE_NEW_CUSTOMER, create new customer & finalize order
    #  if action is MUST_USE_EXISTING_CUSTOMER, attach given customer ID & finalize order
    begin
      Order.transaction do
        order_hash.each_pair do |order_id, o|
          order = Order.find order_id
          order.ticket_sales_import = import
          sold_on = Time.zone.parse o[:transaction_date]
          if o[:action] == ImportableOrder::MAY_CREATE_NEW_CUSTOMER && o[:customer_id].blank?
            order.finalize_with_new_customer!(o[:first], o[:last], o[:email], sold_on)
            import.new_customers += 1
          else
            order.finalize_with_existing_customer_id!(o[:customer_id], sold_on)
            import.existing_customers += 1
          end
          import.tickets_sold += order.ticket_count unless o[:action] == ImportableOrder::ALREADY_IMPORTED
        end
        import.save!
        if import.tickets_sold == 0
          flash[:notice] = t('import.empty_import')
        else
          flash[:notice] = t('import.import_successful', :tickets_sold => import.tickets_sold, :new_customers => import.new_customers, :existing_customers => import.existing_customers)
        end
      end
    rescue StandardError => e
      flash[:alert] = t('import.import_failed', :message => e.message)
    end
    redirect_to ticket_sales_imports_path
  end
end
