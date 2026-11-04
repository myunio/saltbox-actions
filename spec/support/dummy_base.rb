# What the dummy app's ApplicationAction says about its callers, for a base
# class the specs build straight on Saltbox::Actions::Base: a dummy User is a
# plain object holding permission names, and its org is found by id.
module DummyBase
  extend ActiveSupport::Concern

  class_methods do
    def permissions_held(caller) = ApplicationAction.permissions_held(caller)

    def with_schema_user(&) = ApplicationAction.with_schema_user(&)
  end

  def current_tenant = current_user.respond_to?(:org_id) ? Org.find_or_create_by!(id: current_user.org_id) : super
end
