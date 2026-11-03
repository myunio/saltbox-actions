module Saltbox
  module Actions
    # The running invocation, its id, the records it has changed so far, and
    # whether its input went through Arguments#validate!. Rails resets it with
    # every other CurrentAttributes after each request and job.
    # @api private
    class Current < ActiveSupport::CurrentAttributes
      attribute :invocation, :invocation_id, :changes, :arguments_checked
    end
  end
end
