# The dummy app's approvals, as `rails g actions:approvals` writes the model.
# Its people are plain objects, so it has no belongs_to :user.
class ActionApproval < ApplicationRecord
  include Saltbox::Actions::Adapters::Confirmation::Approvals
end
