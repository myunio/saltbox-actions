# What the gem does around every call with nothing for the app to write:
# fresh reads, the caller found again by convention, a strict tenant, the
# app's Current, and the audit stamp.
RSpec.describe "The gem's built-ins" do
  let(:org) { Org.find_or_create_by!(id: 1) }
  # A person kept in a tenant, as an app's Account is.
  let(:member_class) do
    Class.new(ApplicationRecord) do
      self.table_name = "events"
      def self.name = "Member"
      acts_as_tenant :org
    end
  end
  let(:member) { ActsAsTenant.with_tenant(org) { member_class.create!(title: "Ada") } }

  # The gem's own refresh_caller, under a base class of the dummy app's,
  # which otherwise keeps every caller as it stands.
  def with_gem_refresh
    base = Class.new(ApplicationAction) do
      define_method(:refresh_caller) { Saltbox::Actions::Callbacks.instance_method(:refresh_caller).bind_call(self) }
      private :refresh_caller
    end
    stub_const("TestBase", base)
    with_settings(base_class: "TestBase") { yield base }
  end

  def within(caller, &) = Saltbox::Actions.within(caller, &)

  describe "reading fresh" do
    it "reads past Active Record's query cache for the whole call, the refresh included" do
      states = []
      with_gem_refresh do |base|
        base.before_invocation { states << ActiveRecord::Base.connection.query_cache_enabled }
        ActiveRecord::Base.cache do
          within(as_screen(manager)) { states << ActiveRecord::Base.connection.query_cache_enabled }
          states << ActiveRecord::Base.connection.query_cache_enabled
        end
      end
      expect(states).to eq([false, false, true])
    end
  end

  describe "finding the caller again" do
    it "asks the person's class find_for_actions, and refuses the person when it finds no one" do
      looked_up = []
      member_class.define_singleton_method(:find_for_actions) { |id| find_by(id: looked_up.push(id).last) }
      with_gem_refresh do
        expect(within(as_screen(member)) { |fresh| fresh.user }).to eq(member)
        member_class.define_singleton_method(:find_for_actions) { |_id| nil }
        expect { within(as_screen(member)) { raise "ran" } }.to raise_error(Saltbox::Actions::Error::Unauthorized)
      end
      expect(looked_up).to eq([member.id])
    end

    it "reloads a person whose class has no find_for_actions, outside any tenant" do
      with_gem_refresh do
        fresh = within(as_screen(member)) { |caller| caller.user }
        expect(fresh).to eq(member)
        expect(fresh).not_to equal(member)
      end
    end

    it "asks what built a credential's caller to revalidate it, and refuses one nothing vouches for" do
      issuer = Module.new do
        def self.revalidate!(caller) = (caller.credential_id == "live") ? caller.with(scopes: ["events.read"]) : nil
      end
      live = Saltbox::Actions::Caller.new(user: member, surface: "mcp", credential_id: "live", issued_by: issuer)
      with_gem_refresh do
        expect(within(live) { |fresh| fresh.scopes }).to eq(["events.read"])
        expect { within(live.with(credential_id: "revoked")) { raise "ran" } }.to raise_error(Saltbox::Actions::Error::Unauthorized)
        expect { within(live.with(issued_by: nil)) { raise "ran" } }.to raise_error(Saltbox::Actions::Error::Unauthorized)
      end
    end

    it "carries what built the caller to a job" do
      issuer = Module.new.tap { stub_const("TokenSignIn", it) }
      caller = Saltbox::Actions::Caller.new(user: manager, surface: "mcp", credential_id: "t1", issued_by: issuer)
      serialized = ActiveJob::Arguments.serialize([Saltbox::Actions::Adapters::EntryPoints::InvocationJob.serialize_caller(caller)])
      expect(ActiveJob::Arguments.deserialize(serialized).first).to include("issued_by" => TokenSignIn)
    end
  end

  describe "a strict tenant" do
    it "refuses a query on a tenant's model outside any tenant inside a call, and only there" do
      member
      system = Saltbox::Actions::Caller.system
      expect { within(system) { member_class.count } }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
      expect(within(system) { ActsAsTenant.without_tenant { member_class.count } }).to eq(1)
      expect(within(as_screen(manager)) { member_class.count }).to eq(1)
      expect(member_class.count).to eq(1)
    end

    it "adds to the app's own require_tenant" do
      ActsAsTenant.configure { it.require_tenant = true }
      expect(ActsAsTenant.should_require_tenant?).to be(true)
    ensure
      ActsAsTenant.configure { it.require_tenant = false }
    end
  end

  describe "the app's Current" do
    let(:current) do
      Class.new(ActiveSupport::CurrentAttributes) do
        attribute :member, :session, :org, :agent, :surface, :connection, :invocation_id, :cache
        attribute :locale, default: "en"

        # A writer that sets another attribute, as a session= that sets the account does.
        def session=(value)
          super
          self.member = value&.fetch(:member)
        end
      end
    end
    let(:connection) { Struct.new(:id, :label, :approved_at).new(7, "Office computer", Time.utc(2026, 11, 2, 14)) }
    let(:agent) { Saltbox::Actions::Caller.new(user: member, surface: "mcp", agent_name: "Claude", connection:) }

    before { stub_const("Current", current) }

    it "sets the person, the tenant, the agent's stamp and the call on a fresh Current" do
      Current.set(session: {member: :outer}, cache: :outer, locale: "fr") do
        inside = within(agent) { Current.attributes }
        expect(inside).to eq(member:, org:, agent: {"name" => "Claude", "machine" => "Office computer", "connection_id" => 7,
                                                    "connected_at" => "2026-11-02T14:00:00Z"},
          surface: "mcp", connection:, invocation_id: nil, locale: "en")
      end
    end

    it "puts back what it found after the call, error or not, without running a writer" do
      Current.session = {member: :outer}
      Current.member = :changed_after_session
      found = Current.attributes
      expect { within(agent) { raise "boom" } }.to raise_error("boom")
      expect(Current.attributes).to eq(found)
    end

    it "runs the call in the tenant's time zone" do
      org.define_singleton_method(:time_zone) { ActiveSupport::TimeZone["Pacific/Auckland"] }
      allow(Org).to receive(:find_or_create_by!).and_return(org)
      expect(within(as_screen(manager)) { Time.zone.name }).to eq("Pacific/Auckland")
      expect(Time.zone.name).to eq("UTC")
    end

    it "leaves a system caller's Current as it is" do
      Current.cache = :job
      expect(within(Saltbox::Actions::Caller.system) { Current.cache }).to eq(:job)
    end
  end

  describe "the audit stamp" do
    let(:connection) { Struct.new(:id, :label, :approved_at).new(7, "Office computer", Time.utc(2026, 11, 2, 14)) }
    let(:update) do
      Class.new(ApplicationAction) do
        def self.name = "Events::UpdateAction"
        attribute :title, :string
        def perform = event.update!(title:) && render(json: {})
      end
    end

    it "fills each of agent, agent_via, surface, connection_id and invocation_id the versions table has" do
      event = Event.create!(org_id: 1, title: "AGM")
      caller = Saltbox::Actions::Caller.new(user: manager, surface: "mcp", agent_name: "Claude", connection:)
      Saltbox::Actions::Invocation.call(action: update, caller:, arguments: {id: event.id.to_s, title: "Gala"})
      version = PaperTrail::Version.where(item_id: event.id.to_s, event: "update").sole
      expect(version).to have_attributes(agent: "Claude", surface: "mcp", connection_id: 7, invocation_id: match(/\A\h{8}-/),
        agent_via: {"name" => "Claude", "machine" => "Office computer", "connection_id" => 7, "connected_at" => "2026-11-02T14:00:00Z"})
    end

    it "leaves out a column the versions table does not have" do
      allow(Saltbox::Actions::Adapters::Audit::PaperTrail).to receive(:columns).and_return(%w[agent])
      action = ApplicationAction.new(current_caller: as_mcp(manager))
      expect(action.send(:info_for_paper_trail)).to eq(agent: as_mcp(manager).agent_name)
    end
  end
end
