# Changes gem settings for one example and puts them back after it.
module Settings
  def with_settings(**settings)
    config = Saltbox::Actions.config
    before = settings.to_h { |name, _| [name, config.public_send(name)] }
    settings.each { |name, value| config.public_send(:"#{name}=", value) }
    yield
  ensure
    before&.each { |name, value| config.public_send(:"#{name}=", value) }
  end

  # Runs the example with a configuration at its defaults, then puts the
  # dummy app's back.
  #
  # @yieldparam config [Saltbox::Actions::Configuration]
  def with_fresh_config
    original = Saltbox::Actions.config
    Saltbox::Actions.reset_config!
    yield Saltbox::Actions.config
  ensure
    Saltbox::Actions.instance_variable_set(:@config, original)
  end
end

RSpec.configure { |config| config.include Settings }

# Adds a rescue_from to the dummy app's base class for one example, as the
# app would declare it, then takes it away.
module Rescues
  def with_rescue_from(error, handler)
    original = ApplicationAction.rescue_handlers
    ApplicationAction.rescue_from(error, &handler)
    yield
  ensure
    ApplicationAction.rescue_handlers = original
  end

  # The person's approval of the waiting request, as they give it on the app's screen.
  def approve_waiting(user)
    ActsAsTenant.with_tenant(Org.find_or_create_by!(id: user.org_id)) { Saltbox::Actions::Approval.waiting_for(user).sole.approve! }
  end
end

RSpec.configure { |config| config.include Rescues }
