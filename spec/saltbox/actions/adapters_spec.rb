require "open3"

# The optional adapters load only when config.adapters declares them, and
# each declaration is checked as it is made.
RSpec.describe Saltbox::Actions::Adapters do
  let(:config) { Saltbox::Actions::Configuration.new }

  # Runs Ruby with only the gem's lib on the load path beside the bundle, as
  # an app that requires saltbox-actions and has not booted yet.
  def ruby(source)
    Open3.capture2e(RbConfig.ruby, "-Ilib", "-rbundler/setup", "-e", source, chdir: File.expand_path("../../..", __dir__))
  end

  it "refuses a name that is not an adapter, listing the adapters" do
    expect { config.adapters = [:pundit, :sidekiq] }
      .to raise_error(ArgumentError, /:sidekiq is not an adapter. The adapters are :pundit, :action_policy, :controller/)
  end

  it "refuses two authorization adapters" do
    expect { config.adapters = [:pundit, :action_policy] }
      .to raise_error(ArgumentError, "config.adapters declares :pundit and :action_policy: an app authorizes its actions with one; keep one")
  end

  it "refuses an adapter whose gem is not in the bundle, naming the gem to add" do
    missing = described_class::Adapter.new(:fake, :audit, "Fake", "saltbox_actions_no_such_gem", "a fake", nil)
    stub_const("#{described_class}::LIST", described_class::LIST.merge(fake: missing))
    expect { config.adapters = [:fake] }.to raise_error(described_class::MissingGem,
      'config.adapters declares :fake, which needs the saltbox_actions_no_such_gem gem: add gem "saltbox_actions_no_such_gem" to the Gemfile')
  end

  it "takes names as strings too, once each" do
    config.adapters = ["mcp", :mcp, :controller]
    expect(config.adapters).to eq(%i[mcp controller])
  end

  it "includes the declared authorization adapter in the app's base class, which never includes it itself" do
    expect(ApplicationAction.include?(described_class::Authorization::Pundit)).to be(true)
    source = File.read(File.expand_path("../../rails_app/app/actions/application_action.rb", __dir__))
    expect(source).not_to match(/^\s*include /)
  end

  it "leaves every other class on Base without one" do
    expect(Class.new(Saltbox::Actions::Base).include?(described_class::Authorization::Pundit)).to be(false)
  end

  it "installs PaperTrail's change notes once :paper_trail is declared" do
    expect(described_class::Audit::PaperTrail).to be_installed
  end

  describe "in an app that has declared none" do
    it "loads no adapter's gem" do
      output, status = ruby(<<~RUBY)
        require "saltbox/actions"
        puts %w[Pundit ActionPolicy MCP RubyLLM PaperTrail].reject { Object.const_defined?(it) }.join(",")
      RUBY
      expect(status).to be_success, output
      expect(output.strip).to eq("Pundit,ActionPolicy,MCP,RubyLLM,PaperTrail")
    end

    it "names the line to add when code uses an adapter" do
      output, = ruby(<<~RUBY)
        require "saltbox/actions"
        begin
          Saltbox::Actions::Adapters::FrontDoors::MCP
        rescue Saltbox::Actions::Adapters::NotDeclared => error
          puts error.message
        end
      RUBY
      expect(output).to include("Saltbox::Actions::Adapters::FrontDoors::MCP is an optional adapter the app has not declared: " \
        "add :mcp to config.adapters in config/initializers/actions.rb")
    end

    it "names the line to add when an action runs later" do
      output, = ruby(<<~RUBY)
        require "saltbox/actions"
        begin
          Saltbox::Actions::Base.perform_later(caller: Saltbox::Actions::Caller.system)
        rescue Saltbox::Actions::Adapters::NotDeclared => error
          puts error.message
        end
      RUBY
      expect(output).to include("add :invocation_job to config.adapters")
    end

    it "names the require for a test helper" do
      output, = ruby(<<~RUBY)
        require "saltbox/actions"
        begin
          Saltbox::Actions::Adapters::Testing::RSpec
        rescue Saltbox::Actions::Adapters::NotDeclared => error
          puts error.message
        end
      RUBY
      expect(output).to include('require "saltbox/actions/adapters/testing/rspec" in spec/rails_helper.rb')
    end
  end

  it "loads :invocation_job with Active Job, not before" do
    output, status = ruby(<<~RUBY)
      require "saltbox/actions"
      Saltbox::Actions.configure { it.adapters = [:invocation_job] }
      puts defined?(ActiveJob::Base).inspect
      puts Saltbox::Actions::Adapters::FrontDoors::InvocationJob.superclass
    RUBY
    expect(status).to be_success, output
    expect(output.lines.map(&:strip)).to eq(["nil", "ActiveJob::Base"])
  end
end
