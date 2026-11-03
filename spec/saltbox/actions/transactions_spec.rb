# A change against the real database, outside the example's own
# transaction, so commits and rollbacks happen as they do in an app.
RSpec.describe "Changes and transactions" do
  self.use_transactional_tests = false

  let!(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:update) { ->(title) { Saltbox::Actions::Invocation.call(name: "update_event", caller: as_screen(manager), arguments: {id: event.id.to_s, title:}) } }

  after do
    Event.delete_all
    PaperTrail::Version.delete_all
    Dummy::ANNOUNCED.clear
  end

  it "undoes a failed change inside the caller's own transaction, even when the caller rescues it" do
    allow(Saltbox::Actions.config).to receive(:on_changes).and_return(->(*) { raise Saltbox::Actions::Error::Invalid, "store failed" })
    ActiveRecord::Base.transaction do
      update.call("Gone")
    rescue Saltbox::Actions::Error::Invalid
      nil
    end
    expect(event.reload.title).to eq("AGM")
  end

  it "runs after_change once every enclosing transaction commits, and never on rollback" do
    seen = []
    allow(Saltbox::Actions.config).to receive(:after_change)
      .and_return(->(invocation, _) { seen << [invocation.action.action_name, ActiveRecord::Base.connection.transaction_open?] })

    ActiveRecord::Base.transaction do
      update.call("Rolled back")
      expect(seen).to be_empty
      raise ActiveRecord::Rollback
    end
    expect(seen).to be_empty
    expect(event.reload.title).to eq("AGM")

    ActiveRecord::Base.transaction do
      update.call("Annual meeting")
      expect(seen).to be_empty
    end
    expect(seen).to eq([["update_event", false]])

    update.call("Annual general meeting")
    expect(seen.last).to eq(["update_event", false])
  end

  it "keeps the invocation's id for an after_change deferred past its run" do
    ids = []
    allow(Saltbox::Actions.config).to receive(:after_change).and_return(->(invocation, _) { ids << invocation.invocation_id })
    ActiveRecord::Base.transaction { update.call("Annual meeting") }
    expect(ids).to contain_exactly(a_string_matching(/\A\h{8}-/))
  end

  it "does not note writes made in commit callbacks, which run after on_changes" do
    stub_const("Booking", Class.new(ApplicationRecord) {
      self.table_name = "events"
      before_commit { Event.create!(org_id: 1, title: "Before commit") }
      after_create_commit { Event.create!(org_id: 1, title: "After commit") }
    })
    action = Class.new(ApplicationAction) do
      def self.name = "Events::BookAction"
      kind :change
      agents :allowed
      policy_rule :update?

      def perform
        authorize policy_scope(Event).first
        Booking.create!(org_id: 1, title: "Booking")
        head :no_content
      end
    end
    Saltbox::Actions::Invocation.call(name: action, caller: as_screen(manager))
    expect(Event.pluck(:title)).to include("Before commit", "After commit")
    expect(Dummy::ANNOUNCED.sole[:changes]).to eq([["Booking", Event.find_by!(title: "Booking").id.to_s, "create"]])
  end

  describe "a model in a second database" do
    let(:database) { File.expand_path("../../rails_app/tmp/archive.sqlite3", __dir__) }

    before do
      FileUtils.mkdir_p(File.dirname(database))
      stub_const("ArchiveRecord", Class.new(ActiveRecord::Base) { self.abstract_class = true })
      ArchiveRecord.establish_connection(adapter: "sqlite3", database:)
      ArchiveRecord.connection_pool.with_connection { it.create_table(:entries, force: true) { |t| t.string :title } }
      stub_const("Entry", Class.new(ArchiveRecord) { include Saltbox::Actions::ChangeTracking })
      stub_const("EntryPolicy", Class.new(EventPolicy))
    end

    after { ArchiveRecord.remove_connection }

    # Writes an entry, then fails.
    let(:action) do
      Class.new(ApplicationAction) do
        def self.name = "Entry::AddAction"
        kind :change
        agents :allowed
        policy_rule :update?

        def perform
          authorize Event.first
          Entry.create!(title: "Half done")
          raise Saltbox::Actions::Error::Invalid, "No"
        end
      end
    end

    it "does not undo a write to that database from an action whose model is in the first" do
      action = Class.new(ApplicationAction) do
        def self.name = "Events::ArchiveAction"
        kind :change
        agents :allowed
        policy_rule :update?

        def perform
          event = policy_scope(Event).first
          authorize event
          event.update!(title: "Archived")
          Entry.create!(title: "Archived AGM")
          raise Saltbox::Actions::Error::Invalid, "No"
        end
      end
      expect { Saltbox::Actions::Invocation.call(name: action, caller: as_screen(manager)) }.to raise_error(Saltbox::Actions::Error::Invalid)
      expect(event.reload.title).to eq("AGM")
      expect(Entry.count).to eq(1)
    end

    it "runs the change in that model's transaction, so a failure undoes it" do
      expect { Saltbox::Actions::Invocation.call(name: action, caller: as_screen(manager)) }.to raise_error(Saltbox::Actions::Error::Invalid)
      expect(Entry.count).to eq(0)
    end
  end
end
