# The person an action acts for. A plain object here; an app's is usually a
# model. It holds permission names, or :all. A job finds it again by its
# GlobalID, as it would a record.
class User
  include GlobalID::Identification

  attr_reader :id, :org_id, :permissions

  # @return [User] the user made with this id, as a record would be found
  def self.find(id) = known.fetch(id.to_i)

  def self.known = @known ||= {}

  def initialize(id:, org_id: 1, permissions: [])
    @id = id
    @org_id = org_id
    @permissions = permissions
    self.class.known[id] = self
  end

  def can?(permission) = permissions == :all || permissions.include?(permission)
end
