# The invocation callbacks: refresh_caller first, then each declared
# adapter's, then the app's, around every call, actions list and search
# (Saltbox::Actions.within).
RSpec.describe "Running as a caller" do
  let(:seen) { [] }
  let(:event) { Event.create!(org_id: 1, title: "AGM") }

  # A base class of the dummy app's, with a refresh_caller that notes what
  # it sees, made the app's base class for the example.
  def with_base(refreshed: nil)
    seen = self.seen
    base = Class.new(ApplicationAction) do
      define_method(:refresh_caller) do
        seen << [:refresh, current_user.id, ActsAsTenant.current_tenant&.id]
        refreshed ? current_caller.with(user: refreshed) : current_caller
      end
      private :refresh_caller
    end
    stub_const("TestBase", base)
    with_settings(base_class: "TestBase") { yield base }
  end

  def show_action(base)
    Class.new(base) do
      def self.name = "Events::ShowAction"
      def perform = render(json: {title: event.title})
    end
  end

  it "refreshes the caller first, outside any tenant, then sets the tenant, then runs the app's callbacks in order" do
    log = seen
    with_base(refreshed: reader) do |base|
      base.before_invocation { log << [:before, current_user.id, ActsAsTenant.current_tenant&.id] }
      base.around_invocation do |_, block|
        log << [:around, current_user.id]
        block.call
        log << [:after_around]
      end
      base.before_invocation { log << [:inside_around] }
      result = Saltbox::Actions.within(as_screen(manager)) { |fresh| log << [:block, fresh.user.id] and :done }
      expect(result).to eq(:done)
    end
    expect(log).to eq([[:refresh, manager.id, nil], [:before, reader.id, 1], [:around, reader.id], [:inside_around], [:block, reader.id], [:after_around]])
  end

  it "runs the same callbacks around an invocation, with the refreshed caller on the action and the invocation" do
    log = seen
    with_base(refreshed: reader) do |base|
      base.before_invocation { log << [:before, current_caller.user.id] }
      invocation = Saltbox::Actions::Invocation.new(show_action(base), as_screen(manager))
      invocation.call({id: event.id.to_s})
      log << [:invocation, invocation.caller.user.id]
      expect(invocation.invocation_id).to match(/\A\h{8}-/)
    end
    expect(log).to eq([[:refresh, manager.id, nil], [:before, reader.id], [:invocation, reader.id]])
  end

  it "lets a refresh or a callback refuse the call, a list or a search" do
    with_base(refreshed: stranger) do |base|
      expect { Saltbox::Actions::Invocation.call(action: show_action(base), caller: as_screen(manager), arguments: {id: event.id.to_s}) }
        .to be_refused.with(:forbidden)
    end
    with_base do |base|
      base.before_invocation(if: -> { current_caller.surface.assistant? }) { raise Saltbox::Actions::Error::Forbidden }
      expect { Saltbox::Actions::Invocation.call(action: show_action(base), caller: as_assistant(manager), arguments: {id: event.id.to_s}) }
        .to be_refused.with(:forbidden)
      expect { Saltbox::Actions::AgentTools.call("find_action", {query: "event"}, caller: as_assistant(manager)) }
        .to raise_error(Saltbox::Actions::Error::Forbidden)
      expect(Saltbox::Actions::Invocation.call(action: show_action(base), caller: as_mcp(manager), arguments: {id: event.id.to_s}).body)
        .to eq("title" => "AGM")
    end
  end

  it "refuses when a callback halts the chain, and passes a callback's own error on untranslated" do
    with_base do |base|
      base.before_invocation { throw :abort }
      expect { Saltbox::Actions.within(as_screen(manager)) { raise "ran" } }.to be_refused.with(:forbidden)
    end
    with_base do |base|
      base.before_invocation { raise ActiveRecord::RecordNotFound }
      expect { Saltbox::Actions::Invocation.call(action: show_action(base), caller: as_screen(manager), arguments: {id: event.id.to_s}) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "runs perform callbacks inside the invocation's, inside the audit trail's request and outside the change's transaction" do
    log = seen
    with_base do |base|
      base.around_invocation do |_, block|
        log << :invocation
        block.call
      end
      base.around_perform do |_, block|
        log << [:perform, ActiveRecord::Base.connection.open_transactions]
        block.call
        log << [:performed, PaperTrail.request.controller_info]
      end
      action = Class.new(base) do
        def self.name = "Events::UpdateAction"
        def perform
          event.update!(permitted_attributes(event))
          head :no_content
        end
      end
      depth = ActiveRecord::Base.connection.open_transactions
      Saltbox::Actions::Invocation.call(action:, caller: as_mcp(manager), arguments: {id: event.id.to_s, title: "Moved"})
      expect(log.drop(1).first(2)).to eq([:invocation, [:perform, depth]])
      expect(log.last).to match([:performed, include(agent: "RSpec agent", surface: "mcp", invocation_id: a_string_matching(/\A\h{8}-/))])
    end
  end

  it "runs the adapters' callbacks in one order, whatever the order of config.adapters" do
    log = seen
    declared = Saltbox::Actions.config.adapters
    orders = [declared, declared.reverse].map do |adapters|
      with_settings(adapters:) do
        log.clear
        with_base do |base|
          base.before_invocation { log << [:tenant, ActsAsTenant.current_tenant&.id] }
          base.around_perform do |_, block|
            log << [:audit, PaperTrail.request.controller_info&.key?(:invocation_id)]
            block.call
          end
          Saltbox::Actions::Invocation.call(action: show_action(base), caller: as_screen(manager), arguments: {id: event.id.to_s})
        end
        log.dup
      end
    end
    expect(orders.first).to eq([[:refresh, manager.id, nil], [:tenant, 1], [:audit, true]])
    expect(orders.last).to eq(orders.first)
  end

  describe "the gem's own refresh_caller" do
    def refreshed(caller) = Saltbox::Actions::Base.new(current_caller: caller).send(:refresh_caller)

    it "reloads an Active Record person, and refuses one who is gone" do
      stale = Org.create!
      fresh = refreshed(Saltbox::Actions::Caller.screen(stale))
      expect(fresh.user).to eq(stale)
      expect(fresh.user).not_to equal(stale)
      gone = Org.find(stale.id)
      stale.destroy!
      expect { refreshed(Saltbox::Actions::Caller.screen(gone)) }.to raise_error(Saltbox::Actions::Error::Unauthorized)
    end

    it "refuses a caller holding a credential, which only the app knows how to check" do
      expect { refreshed(Saltbox::Actions::Caller.new(user: manager, surface: "mcp", credential_id: "t1")) }.to raise_error(Saltbox::Actions::Error::Unauthorized)
      expect { refreshed(Saltbox::Actions::Caller.new(user: manager, surface: "mcp", connection: Object.new)) }.to raise_error(Saltbox::Actions::Error::Unauthorized)
    end

    it "keeps any other caller as it is" do
      caller = Saltbox::Actions::Caller.system
      expect(refreshed(caller)).to equal(caller)
      expect(refreshed(as_screen(manager)).user).to equal(manager)
    end

    it "must give back a caller" do
      with_base do |base|
        base.define_method(:refresh_caller) { nil }
        expect { Saltbox::Actions.within(as_screen(manager)) { nil } }.to raise_error(ArgumentError, /refresh_caller returned nil: return a Caller/)
      end
    end
  end

  describe "the :acts_as_tenant adapter" do
    it "runs every call in the caller's tenant, and refuses a person with none, never running unscoped" do
      expect(Saltbox::Actions.within(as_screen(other_org_manager)) { ActsAsTenant.current_tenant.id }).to eq(2)
      with_base do |base|
        base.define_method(:current_tenant) { nil }
        expect { Saltbox::Actions.within(as_screen(manager)) { raise "ran" } }.to be_refused.with(:forbidden)
      end
    end

    it "keeps the tenant around a system caller, such as a job's" do
      org = Org.find_or_create_by!(id: 3)
      expect(ActsAsTenant.with_tenant(org) { Saltbox::Actions.within(Saltbox::Actions::Caller.system) { ActsAsTenant.current_tenant } }).to eq(org)
    end

    it "takes the tenant of a person's model from the association acts_as_tenant keeps on it" do
      member = Class.new(ApplicationRecord) do
        self.table_name = "events"
        def self.name = "Member"
        acts_as_tenant :org
      end
      org = Org.find_or_create_by!(id: 1)
      person = ActsAsTenant.with_tenant(org) { member.create!(title: "Ada") }
      tenancy = Saltbox::Actions::Adapters::Tenancy::ActsAsTenant
      expect(tenancy.tenant_of(person)).to eq(org)
      expect(tenancy.tenant_of(Event.new(org_id: 1))).to be_nil
      expect(tenancy.tenant_of(manager)).to be_nil
    end
  end
end
