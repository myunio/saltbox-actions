module Saltbox
  module Actions
    # The running invocation, its id, and the records it has changed so far.
    # Rails resets it with every other CurrentAttributes after each request
    # and job.
    # @api private
    class Current < ActiveSupport::CurrentAttributes
      attribute :invocation, :invocation_id, :changes
    end
  end
end
