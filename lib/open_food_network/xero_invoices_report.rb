module OpenFoodNetwork
  class XeroInvoicesReport
    def initialize(orders, opts={})
      @orders = orders

      @opts = opts.
              reject { |k, v| v.blank? }.
              reverse_merge({report_type: 'summary',
                             invoice_date: Date.today,
                             due_date: 2.weeks.from_now.to_date,
                             account_code: 'food sales'})
    end

    def header
      %w(*ContactName EmailAddress POAddressLine1 POAddressLine2 POAddressLine3 POAddressLine4 POCity PORegion POPostalCode POCountry *InvoiceNumber Reference *InvoiceDate *DueDate InventoryItemCode *Description *Quantity *UnitAmount Discount *AccountCode *TaxType TrackingName1 TrackingOption1 TrackingName2 TrackingOption2 Currency BrandingTheme Paid?)
    end

    def table
      rows = []

      @orders.each_with_index do |order, i|
        invoice_number = invoice_number_for(order, i)
        rows += detail_rows_for_order(order, invoice_number, @opts) if detail?
        rows += summary_rows_for_order(order, invoice_number, @opts)
      end

      rows.compact
    end


    private

    def detail_rows_for_order(order, invoice_number, opts)
      rows = []

      rows += line_item_detail_rows(order, invoice_number, opts)

      if order.account_invoice?
        rows += adjustment_detail_rows(order, invoice_number, opts)
      end

      rows
    end

    def line_item_detail_rows(order, invoice_number, opts)
      order.line_items.map do |line_item|
        line_item_detail_row(line_item, invoice_number, opts)
      end
    end

    def line_item_detail_row(line_item, invoice_number, opts)
      row(line_item.order,
          line_item.product.sku,
          line_item.variant.product_and_variant_name,
          line_item.quantity.to_s,
          line_item.price.to_s,
          invoice_number,
          tax_type(line_item),
          opts)
    end

    def adjustment_detail_rows(order, invoice_number, opts)
      account_invoice_adjustments(order).map do |adjustment|
        adjustment_detail_row(adjustment, invoice_number, opts)
      end
    end

    def adjustment_detail_row(adjustment, invoice_number, opts)
      row(adjustment.source.andand.account_invoice.andand.order,
          '',
          adjustment.label,
          1,
          adjustment.amount,
          invoice_number,
          tax_type(adjustment),
          opts)
    end

    def summary_rows_for_order(order, invoice_number, opts)
      rows = []

      rows += produce_summary_rows(order, invoice_number, opts)  unless detail?
      rows += fee_summary_rows(order, invoice_number, opts)      unless detail? && order.account_invoice?
      rows += shipping_summary_rows(order, invoice_number, opts)

      rows
    end

    def produce_summary_rows(order, invoice_number, opts)
      [summary_row(order, 'Total untaxable produce (no tax)',       total_untaxable_products(order), invoice_number, 'GST Free Income',        opts),
       summary_row(order, 'Total taxable produce (tax inclusive)',  total_taxable_products(order),   invoice_number, 'GST on Income',          opts)]
    end

    def fee_summary_rows(order, invoice_number, opts)
      [summary_row(order, 'Total untaxable fees (no tax)',          total_untaxable_fees(order),     invoice_number, 'GST Free Income',        opts),
       summary_row(order, 'Total taxable fees (tax inclusive)',     total_taxable_fees(order),       invoice_number, 'GST on Income',          opts)]
    end

    def shipping_summary_rows(order, invoice_number, opts)
      [summary_row(order, 'Delivery Shipping Cost (tax inclusive)', total_shipping(order),           invoice_number, tax_on_shipping_s(order), opts)]
    end

    def summary_row(order, description, amount, invoice_number, tax_type, opts={})
      row order, '', description, '1', amount, invoice_number, tax_type, opts
    end

    def row(order, sku, description, quantity, amount, invoice_number, tax_type, opts={})
      return nil if amount == 0

      [order.bill_address.andand.full_name,
       order.email,
       order.bill_address.andand.address1,
       order.bill_address.andand.address2,
       '',
       '',
       order.bill_address.andand.city,
       order.bill_address.andand.state,
       order.bill_address.andand.zipcode,
       order.bill_address.andand.country.andand.name,
       invoice_number,
       order.number,
       opts[:invoice_date],
       opts[:due_date],
       sku,
       description,
       quantity,
       amount,
       '',
       opts[:account_code],
       tax_type,
       '',
       '',
       '',
       '',
       Spree::Config.currency,
       '',
       order.paid? ? 'Y' : 'N'
      ]
    end

    def account_invoice_adjustments(order)
      order.adjustments.
        billable_period.
        select { |a| a.source.present? }
    end

    def invoice_number_for(order, i)
      @opts[:initial_invoice_number] ? @opts[:initial_invoice_number].to_i+i : order.number
    end

    def total_untaxable_products(order)
      order.line_items.without_tax.sum &:amount
    end

    def total_taxable_products(order)
      order.line_items.with_tax.sum &:amount
    end

    def total_untaxable_fees(order)
      order.adjustments.enterprise_fee.without_tax.sum &:amount
    end

    def total_taxable_fees(order)
      order.adjustments.enterprise_fee.with_tax.sum &:amount
    end

    def total_shipping(order)
      order.adjustments.shipping.sum &:amount
    end

    def tax_on_shipping_s(order)
      tax_on_shipping = order.adjustments.shipping.sum(&:included_tax) > 0
      tax_on_shipping ? 'GST on Income' : 'GST Free Income'
    end

    def detail?
      @opts[:report_type] == 'detailed'
    end

    def tax_type(taxable)
      taxable.has_tax? ? 'GST on Income' : 'GST Free Income'
    end
  end
end
