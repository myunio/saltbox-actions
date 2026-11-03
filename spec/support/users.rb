# People for the dummy app's specs.
module Users
  def manager = @manager ||= User.new(id: 1, permissions: %w[events.view events.manage events.delete])
  def reader = @reader ||= User.new(id: 2, permissions: %w[events.view])
  def stranger = @stranger ||= User.new(id: 3, permissions: [])
  def other_org_manager = @other_org_manager ||= User.new(id: 4, org_id: 2, permissions: %w[events.view events.manage events.delete])
end

RSpec.configure do |config|
  config.include Users
  # The gem's own specs use the helpers too; specs under spec/actions get
  # them from `type: :action`, as an app's do.
  config.include Saltbox::Actions::RSpec::Helpers, file_path: %r{/spec/(saltbox|requests)/}
  config.include Saltbox::Actions::RSpec::Matchers, file_path: %r{/spec/(saltbox|requests)/}
end

Saltbox::Actions::RSpec.config.spec_root = File.expand_path("../actions", __dir__)
