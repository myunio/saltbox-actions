# An engine action on the host app's model. Its folder's namespace takes the
# place of the engine's module in its name, list_billing_events, and its
# policy is the engine's, Billing::EventPolicy.
class Billing::Events::ListAction < ApplicationAction
  def perform
    events = policy_scope(Event).order(:id)
    render json: {events: events.map { {id: it.id, title: it.title} }}, collection: events
  end
end
