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
end
