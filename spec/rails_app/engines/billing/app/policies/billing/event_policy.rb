module Billing
  # The engine's policy for the host app's events: billing staff see their
  # organization's.
  class EventPolicy
    attr_reader :user, :record

    def initialize(user, record)
      @user = user
      @record = record
    end

    def index? = user.can?("billing.view")

    class Scope
      def initialize(user, scope)
        @user = user
        @scope = scope
      end

      def resolve = @scope.where(org_id: @user.org_id)
    end
  end
end
