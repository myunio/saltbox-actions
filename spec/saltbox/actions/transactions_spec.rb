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
        connections :allowed
        authorize :update?

        def perform
          authorize Event.first
          Entry.create!(title: "Half done")
          raise Saltbox::Actions::Error::Invalid, "No"
        end
      end
    end

    it "runs the change in that model's transaction, so a failure undoes it" do
      expect { Saltbox::Actions::Invocation.call(name: action, caller: as_screen(manager)) }.to raise_error(Saltbox::Actions::Error::Invalid)
      expect(Entry.count).to eq(0)
    end
  end
end
