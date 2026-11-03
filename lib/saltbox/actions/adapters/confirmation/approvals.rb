require "saltbox/actions/approval"

module Saltbox
  module Actions
    module Adapters
      module Confirmation
        # Declaring :approvals keeps each agent's call to a :confirm action in
        # the gem's saltbox_action_approvals table (Approval) until the person
        # approves it, and makes Approval.redeem! the confirm hook unless the
        # app sets its own.
        module Approvals
          # Declares Approval's associations from Configuration#approvals.
          # Run once the app has loaded, by the :approvals declaration.
          #
          # @return [void]
          def self.install! = Approval.install!(Actions.config.approvals)

          # @return [Proc] the confirm hook while :approvals is declared
          def self.confirm = ->(invocation, action) { Approval.redeem!(invocation, action) }
        end
      end
    end
  end
end
