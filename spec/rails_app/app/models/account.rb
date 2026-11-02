# The person an action acts for. A plain object here; an app's is usually a
# model. It holds permission names, or :all.
class Account
  attr_reader :id, :org_id, :permissions

  def initialize(id:, org_id: 1, permissions: [])
    @id = id
    @org_id = org_id
    @permissions = permissions
  end

  def can?(permission) = permissions == :all || permissions.include?(permission)
end
