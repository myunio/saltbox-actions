# The tenant: approvals are kept in it, and Flipper turns features on for it.
class Org < ApplicationRecord
  def flipper_id = "Org;#{id}"
end
