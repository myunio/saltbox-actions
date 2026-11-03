# The engine's own action spec, beside its app/actions folder.
RSpec.describe Billing::Invoices::ListAction do
  let(:permitted_user) { User.new(id: 5, permissions: %w[billing.view]) }
  let(:unpermitted_user) { stranger }
  let(:arguments) { {} }

  it_behaves_like "refuses callers the action does not allow"

  it "lists the organization's invoices" do
    mine = Billing::Invoice.create!(org_id: 1, number: "INV-1")
    Billing::Invoice.create!(org_id: 2, number: "INV-2")
    expect(run({}, as: as_api(permitted_user)).body["invoices"].pluck("id")).to eq([mine.id])
  end
end
