require 'spec_helper'

def travel_to(time)
  around { |example| Timecop.travel(start_of_july + time) { example.run } }
end

describe UpdateAccountInvoices do
  describe "units specs" do
    let!(:start_of_july) { Time.now.beginning_of_year + 6.months }

    let!(:updater) { UpdateAccountInvoices.new }

    let!(:user) { create(:user) }
    let!(:old_billable_period) { create(:billable_period, owner: user, begins_at: start_of_july - 1.month, ends_at: start_of_july) }
    let!(:billable_period1) { create(:billable_period, owner: user, begins_at: start_of_july, ends_at: start_of_july + 12.days) }
    let!(:billable_period2) { create(:billable_period, owner: user, begins_at: start_of_july + 12.days, ends_at: start_of_july + 20.days) }
    let(:june_account_invoice) { old_billable_period.account_invoice }
    let(:july_account_invoice) { billable_period1.account_invoice }

    describe "perform" do
      let(:accounts_distributor) { double(:accounts_distributor) }
      before do
        allow(Enterprise).to receive(:find_by_id) { accounts_distributor }
        allow(updater).to receive(:update)
        allow(Bugsnag).to receive(:notify)
      end

      context "when necessary global config setting have not been set" do
        travel_to(20.days)

        context "when accounts_distributor has been set" do
          before do
            allow(Enterprise).to receive(:find_by_id) { false }
            updater.perform
          end

          it "snags errors and doesn't run" do
            expect(Bugsnag).to have_received(:notify).with(RuntimeError.new("InvalidJobSettings"), anything)
            expect(updater).to_not have_received(:update)
          end
        end
      end

      context "when necessary global config setting have been set" do
        context "on the first of the month" do
          travel_to(3.hours)

          it "updates invoices from the previous month" do
            updater.perform
            expect(updater).to have_received(:update).once
            .with(june_account_invoice)
            expect(updater).to_not have_received(:update)
            .with(july_account_invoice)
          end
        end

        context "on other days" do
          travel_to(20.days)

          it "updates invoices from the current month" do
            updater.perform
            expect(updater).to have_received(:update).once
            .with(july_account_invoice)
          end
        end

        context "when specfic a specific month (and year) are passed as arguments" do
          let!(:updater) { UpdateAccountInvoices.new(Time.now.year, 7) }

          before do
            allow(updater).to receive(:update)
          end

          context "that just ended (in the past)" do
            travel_to(1.month)

            it "updates invoices from the previous month" do
              updater.perform
              expect(updater).to have_received(:update).once
              .with(july_account_invoice)
            end
          end

          context "that starts in the past and ends in the future (ie. current_month)" do
            travel_to 30.days

            it "updates invoices from that current month" do
              updater.perform
              expect(updater).to have_received(:update).once
              .with(july_account_invoice)
            end
          end

          context "that starts in the future" do
            travel_to -1.days

            it "snags an error and does not update invoices" do
              updater.perform
              expect(Bugsnag).to have_received(:notify).with(RuntimeError.new("InvalidJobSettings"), anything)
              expect(updater).to_not have_received(:update)
            end
          end
        end
      end
    end

    describe "update" do
      before do
        allow(june_account_invoice).to receive(:save).and_call_original
        allow(july_account_invoice).to receive(:save).and_call_original
        allow(updater).to receive(:clean_up)
        allow(updater).to receive(:finalize)
        allow(Bugsnag).to receive(:notify)
      end

      context "where an order for the invoice already exists" do
        let!(:invoice_order) { create(:order, user: user) }

        before do
          expect(Spree::Order).to_not receive(:new)
          allow(june_account_invoice).to receive(:order) { invoice_order }
        end

        context "where the order is already complete" do
          before do
            allow(invoice_order).to receive(:complete?) { true }
            updater.update(june_account_invoice)
          end

          it "snags a bug" do
            expect(Bugsnag).to have_received(:notify)
          end
        end

        context "where the order is not complete" do
          before do
            allow(invoice_order).to receive(:complete?) { false }
            updater.update(june_account_invoice)
          end

          it "creates adjustments for each billing item" do
            adjustments = invoice_order.adjustments
            expect(adjustments.map(&:source_id)).to eq [old_billable_period.id]
            expect(adjustments.map(&:amount)).to eq [old_billable_period.bill]
            expect(adjustments.map(&:label)).to eq [old_billable_period.adjustment_label]
          end

          it "saves the order" do
            expect(june_account_invoice).to have_received(:save)
            expect(june_account_invoice.order).to be_persisted
          end

          it "cleans up the order" do
            expect(updater).to have_received(:clean_up).with(invoice_order, anything).once
          end
        end
      end

      context "where an order for the invoice does not already exist" do
        let!(:accounts_distributor) { create(:distributor_enterprise) }
        before do
          Spree::Config.set({ accounts_distributor_id: accounts_distributor.id })
          updater.update(july_account_invoice)
        end

        it "creates adjustments for each billing item" do
          adjustments = july_account_invoice.order.adjustments
          expect(adjustments.map(&:source_id)).to eq [billable_period1.id, billable_period2.id]
          expect(adjustments.map(&:amount)).to eq [billable_period1.bill, billable_period2.bill]
          expect(adjustments.map(&:label)).to eq [billable_period1.adjustment_label, billable_period2.adjustment_label]
        end

        it "saves the order" do
          expect(july_account_invoice).to have_received(:save)
          expect(july_account_invoice.order).to be_persisted
        end

        it "cleans up order" do
          expect(updater).to have_received(:clean_up).with(july_account_invoice.order, anything).once
        end
      end
    end

    describe "clean_up" do
      let!(:invoice_order) { create(:order) }
      let!(:obsolete1) { create(:adjustment, adjustable: invoice_order) }
      let!(:obsolete2) { create(:adjustment, adjustable: invoice_order) }
      let!(:current1) { create(:adjustment, adjustable: invoice_order) }
      let!(:current2) { create(:adjustment, adjustable: invoice_order) }

      before do
        allow(invoice_order).to receive(:save)
        allow(invoice_order).to receive(:destroy)
        allow(Bugsnag).to receive(:notify)
      end

      context "when current adjustments are present" do
        let!(:current_adjustments) { [current1, current2] }

        context "and obsolete adjustments are present" do
          let!(:obsolete_adjustments) { [obsolete1, obsolete2] }

          before do
            allow(obsolete_adjustments).to receive(:destroy_all)
            allow(invoice_order).to receive(:adjustments) { double(:adjustments, where: obsolete_adjustments) }
            updater.clean_up(invoice_order, current_adjustments)
          end

          it "destroys obsolete adjustments and snags a bug" do
            expect(obsolete_adjustments).to have_received(:destroy_all)
            expect(Bugsnag).to have_received(:notify).with(RuntimeError.new("Obsolete Adjustments"), anything)
          end
        end

        context "and obsolete adjustments are not present" do
          let!(:obsolete_adjustments) { [] }

          before do
            allow(invoice_order).to receive(:adjustments) { double(:adjustments, where: obsolete_adjustments) }
            updater.clean_up(invoice_order, current_adjustments)
          end

          it "has no bugs to snag" do
            expect(Bugsnag).to_not have_received(:notify)
          end
        end
      end

      context "when current adjustments are not present" do
        let!(:current_adjustments) { [] }

        context "and obsolete adjustments are present" do
          let!(:obsolete_adjustments) { [obsolete1, obsolete2] }

          before do
            allow(obsolete_adjustments).to receive(:destroy_all)
            allow(invoice_order).to receive(:adjustments) { double(:adjustments, where: obsolete_adjustments) }
            updater.clean_up(invoice_order, current_adjustments)
          end

          it "destroys obsolete adjustments and snags a bug" do
            expect(obsolete_adjustments).to have_received(:destroy_all)
            expect(Bugsnag).to have_received(:notify).with(RuntimeError.new("Obsolete Adjustments"), anything)
          end

          it "destroys the order and snags a bug" do
            expect(invoice_order).to have_received(:destroy)
            expect(Bugsnag).to have_received(:notify).with(RuntimeError.new("Empty Persisted Invoice"), anything)
          end
        end

        context "and obsolete adjustments are not present" do
          let!(:obsolete_adjustments) { [] }

          before do
            allow(invoice_order).to receive(:adjustments) { double(:adjustments, where: obsolete_adjustments) }
            updater.clean_up(invoice_order, current_adjustments)
          end

          it "has no bugs to snag" do
            expect(Bugsnag).to_not have_received(:notify).with(RuntimeError.new("Obsolete Adjustments"), anything)
          end

          it "destroys the order and snags a bug" do
            expect(invoice_order).to have_received(:destroy)
            expect(Bugsnag).to have_received(:notify).with(RuntimeError.new("Empty Persisted Invoice"), anything)
          end
        end
      end
    end
  end

  describe "validation spec" do
    let!(:start_of_july) { Time.now.beginning_of_year + 6.months }

    let!(:updater) { UpdateAccountInvoices.new }

    let!(:accounts_distributor) { create(:distributor_enterprise) }

    let!(:user) { create(:user) }
    let!(:billable_period1) { create(:billable_period, sells: 'any', owner: user, begins_at: start_of_july - 1.month, ends_at: start_of_july) }
    let!(:billable_period2) { create(:billable_period, owner: user, begins_at: start_of_july, ends_at: start_of_july + 10.days) }
    let!(:billable_period3) { create(:billable_period, owner: user, begins_at: start_of_july + 12.days, ends_at: start_of_july + 20.days) }
    let!(:july_account_invoice) { billable_period2.account_invoice }

    before do
      Spree::Config.set({ accounts_distributor_id: accounts_distributor.id })
    end

    context "when no invoice_order currently exists" do
      context "when relevant billable periods exist" do
        travel_to(20.days)

        it "creates an invoice_order" do
          expect{updater.perform}.to change{Spree::Order.count}.from(0).to(1)
          invoice_order = july_account_invoice.reload.order
          expect(user.orders.first).to eq invoice_order
          expect(invoice_order.completed_at).to be_nil
          billable_adjustments = invoice_order.adjustments.where('source_type = (?)', 'BillablePeriod')
          expect(billable_adjustments.map(&:amount)).to eq [billable_period2.bill, billable_period3.bill]
          expect(invoice_order.total).to eq billable_period2.bill + billable_period3.bill
          expect(invoice_order.payments.count).to eq 0
          expect(invoice_order.state).to eq 'cart'
        end
      end

      context "when no relevant billable periods exist" do
        travel_to(1.month + 5.days)

        it "does not create an order" do
          expect{updater.perform}.to_not change{Spree::Order.count}.from(0)
        end
      end
    end

    context "when an order already exists" do
      let!(:invoice_order) { create(:order, user: user, distributor: accounts_distributor, created_at: start_of_july) }
      let!(:billable_adjustment) { create(:adjustment, adjustable: invoice_order, source_type: 'BillablePeriod') }

      before do
        invoice_order.line_items.clear
        july_account_invoice.update_attribute(:order, invoice_order)
      end

      context "when relevant billable periods exist" do
        travel_to(20.days)

        it "updates the order, and clears any obsolete invoices" do
          expect{updater.perform}.to_not change{Spree::Order.count}
          invoice_order = user.orders.first
          expect(invoice_order.completed_at).to be_nil
          billable_adjustments = invoice_order.adjustments.where('source_type = (?)', 'BillablePeriod')
          expect(billable_adjustments).to_not include billable_adjustment
          expect(billable_adjustments.map(&:amount)).to eq [billable_period2.bill, billable_period3.bill]
          expect(invoice_order.total).to eq billable_period2.bill + billable_period3.bill
          expect(invoice_order.payments.count).to eq 0
          expect(invoice_order.state).to eq 'cart'
        end
      end

      context "when no relevant billable periods exist" do
        travel_to(1.month + 5.days)

        it "destroys the order" do
          expect{updater.perform}.to_not change{Spree::Order.count}.from(1).to(0)
        end
      end
    end
  end
end
