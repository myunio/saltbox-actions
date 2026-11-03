class Billing::Invoices::ListAction < ApplicationAction
  def perform
    authorize Billing::Invoice
    render json: {invoices: policy_scope(Billing::Invoice).order(:id).map { {id: it.id, number: it.number} }}
  end
end
