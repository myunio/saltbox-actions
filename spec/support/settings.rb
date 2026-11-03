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
end

RSpec.configure { |config| config.include Settings }
