require "saltbox/actions/approval"

module Saltbox
  module Actions
    module Adapters
      module Confirmation
        # Declaring :approvals keeps each agent's call to a :confirm action in
        # the gem's saltbox_action_approvals table (Approval) until the person
        # approves it: Invocation asks Approval.redeem! about every such call.
        module Approvals
          # Declares Approval's associations from Configuration#approvals.
          # Run once the app has loaded, by the :approvals declaration.
          #
          # @return [void]
          def self.install! = Approval.install!(Actions.config.approvals)
        end
      end
    end
  end
end
