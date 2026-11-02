module Saltbox
  module Actions
    # The running invocation's id, and the records it has changed so far.
    # Rails resets it with every other CurrentAttributes after each request
    # and job.
    class Current < ActiveSupport::CurrentAttributes
      attribute :invocation_id, :changes
    end
  end
end
