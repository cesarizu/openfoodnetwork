class Admin::AccountController < Spree::Admin::BaseController

  def show
    @invoices = spree_current_user.account_invoices
    # @enterprises = Enterprise.where(id: BillablePeriod.where(owner_id: spree_current_user).map(&:enterprise_id))
    # .group_by('enterprise.id').joins(:billable_periods)
    # .select('SUM(billable_periods.turnover) AS turnover').order('turnover DESC')
  end
end
