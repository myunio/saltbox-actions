RSpec.describe Saltbox::Actions::ChangeTracking do
  let!(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:update) { -> { Saltbox::Actions::Invocation.call(action: "update_event", caller: as_screen(manager), arguments: {id: event.id.to_s, title: "Annual meeting"}) } }

  # Updates the event, and adds a child inside a savepoint it rolls back.
  let(:half_undone) do
    Class.new(ApplicationAction) do
      def self.name = "Events::SplitAction"
      kind :change
      agents :allowed
      policy_rule :update?

      def perform
        event = policy_scope(Event).first
        authorize event
        event.update!(title: "Split")
        Event.transaction(requires_new: true) do
          Event.create!(org_id: 1, title: "Child", parent: event)
          raise ActiveRecord::Rollback
        end
        head :no_content
      end
    end
  end

  def without_paper_trail
    ::PaperTrail.enabled = false
    yield
  ensure
    ::PaperTrail.enabled = true
  end

  it "notes changes without PaperTrail" do
    without_paper_trail do
      expect { update.call }.to announce_changes(event => :update)
    end
    expect(Dummy::ANNOUNCED).to eq([{action: "update_event", changes: [["Event", event.id.to_s, "update"]]}])
    expect(PaperTrail::Version.where(event: "update")).to be_empty
  end

  it "notes creates and destroys" do
    without_paper_trail do
      expect { Saltbox::Actions::Invocation.call(action: "create_event", caller: as_screen(manager), arguments: {title: "New"}) }
        .to announce_changes(Event => :create)
      expect { Saltbox::Actions::Invocation.call(action: "delete_event", caller: as_screen(manager), arguments: {id: event.id.to_s}) }
        .to announce_changes(event => :destroy)
    end
  end

  it "notes nothing for a write a savepoint inside the action rolls back" do
    without_paper_trail { Saltbox::Actions::Invocation.call(action: half_undone, caller: as_screen(manager)) }
    expect(Dummy::ANNOUNCED.sole[:changes]).to eq([["Event", event.id.to_s, "update"]])
  end

  it "notes nothing when the action fails" do
    failing = Class.new(ApplicationAction) do
      def self.name = "Events::BreakAction"
      kind :change
      agents :allowed
      policy_rule :update?

      def perform
        event = policy_scope(Event).first
        authorize event
        event.update!(title: "Broken")
        raise Saltbox::Actions::Error::Invalid, "No"
      end
    end
    expect { expect { Saltbox::Actions::Invocation.call(action: failing, caller: as_screen(manager)) }.to be_refused.with(:validation_failed) }
      .not_to announce_changes
    expect(Dummy::ANNOUNCED).to be_empty
  end

  it "says how to note changes when nothing was announced and nothing notes them" do
    allow(Saltbox::Actions::ChangeTracking).to receive(:in_use?).and_return(false)
    expect { expect {}.to announce_changes(event => :update) }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError, /include Saltbox::Actions::ChangeTracking in ApplicationRecord/)
  end

  it "notes a save that changed nothing as no change" do
    _, changes = Saltbox::Actions::Invocation.collect_changes { event.save! }
    expect(changes).to be_empty
  end

  it "does not note writes that skip callbacks, or touch" do
    _, changes = without_paper_trail do
      Saltbox::Actions::Invocation.collect_changes do
        Event.where(id: event.id).update_all(title: "Bulk")
        event.touch
      end
    end
    expect(changes).to be_empty
  end

  describe "with PaperTrail as the only source" do
    before do
      stub_const("Archive", Class.new(ActiveRecord::Base) { self.table_name = "events" })
      Archive.has_paper_trail
    end

    it "notes each version written, and drops one whose savepoint rolls back" do
      kept = nil
      _, changes = Saltbox::Actions::Invocation.collect_changes do
        ActiveRecord::Base.transaction(requires_new: true) do
          kept = Archive.create!(org_id: 1, title: "Kept")
          ActiveRecord::Base.transaction(requires_new: true) do
            Archive.create!(org_id: 1, title: "Undone")
            raise ActiveRecord::Rollback
          end
        end
      end
      expect(changes).to eq([["Archive", kept.id.to_s, "create"]])
    end
  end
end
