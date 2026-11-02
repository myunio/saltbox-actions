# The ActionPolicy policy for the same model, found through the
# ActionPolicies namespace by the actions that use ActionPolicy.
module ActionPolicies
  class EventPolicy < ActionPolicy::Base
    authorize :user

    default_rule :manage?
    alias_rule :index?, :show?, to: :view?

    def view? = user.can?("events.view")
    def manage? = user.can?("events.manage")
    def destroy? = user.can?("events.delete")

    def permitted_attributes = %i[title starts_on capacity status]

    relation_scope { |relation| relation.where(org_id: user.org_id) }
  end
end
