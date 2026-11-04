require "flipper"
require "pagy"

# The adapters that stand in for 1.2's hooks: :flipper for feature_enabled
# and :pagy for paging, and the settings that are gone.
RSpec.describe "The seam's adapters" do
  let(:event) { Event.create!(org_id: 1, title: "AGM") }

  describe ":flipper" do
    let(:beta) do
      Class.new(ApplicationAction) do
        def self.name = "Events::PreviewAction"
        define_verb :preview, kind: :read, on: :member
        feature "event_preview"
        policy_rule :show?
        def perform = render(json: {title: event.title})
      end
    end
    let(:run) { ->(user) { Saltbox::Actions::Invocation.call(action: beta, caller: as_mcp(user), arguments: {id: event.id.to_s}) } }

    around do |example|
      with_settings(adapters: Saltbox::Actions.config.adapters + [:flipper]) { example.run }
    ensure
      Flipper.disable("event_preview")
    end

    it "hides an action whose feature is off, and runs it once Flipper turns it on for the caller's tenant" do
      expect { run.call(manager) }.to be_not_found
      expect(beta).not_to be_listed_for(as_mcp(manager))
      Flipper.enable_actor("event_preview", Org.find_or_create_by!(id: 1))
      expect(run.call(manager).body).to eq("title" => "AGM")
      expect(beta).to be_listed_for(as_mcp(manager))
      expect(beta).not_to be_listed_for(as_mcp(other_org_manager))
    end

    it "asks for the app's own flipper_actors" do
      Flipper.enable_actor("event_preview", Struct.new(:flipper_id).new("Person;#{manager.id}"))
      expect { run.call(manager) }.to be_not_found
      beta.define_method(:flipper_actors) { [Struct.new(:flipper_id).new("Person;#{current_user.id}")] }
      expect(run.call(manager).body).to eq("title" => "AGM")
    end

    it "leaves every feature on without the adapter" do
      with_settings(adapters: Saltbox::Actions.config.adapters - [:flipper]) do
        expect(run.call(manager).body).to eq("title" => "AGM")
      end
    end
  end

  describe ":pagy" do
    around do |example|
      with_settings(adapters: Saltbox::Actions.config.adapters + [:pagy], list_adapter: nil) { example.run }
    end

    it "takes page_size and max_page_size from Pagy's own settings, unless the app sets them" do
      stub_const("Pagy::OPTIONS", Pagy::OPTIONS.merge(limit: 7, client_limit: 70))
      expect(Saltbox::Actions.config).to have_attributes(page_size: 7, max_page_size: 70)
      adapters = Saltbox::Actions.config.adapters
      with_fresh_config do |config|
        config.adapters = adapters
        config.page_size = 5
        expect(config).to have_attributes(page_size: 5, max_page_size: 70)
        config.adapters = adapters - [:pagy]
        config.page_size = nil
        expect(config).to have_attributes(page_size: 25, max_page_size: 100)
      end
    end

    it "pages a list with Pagy, the list adapter unless the app names its own" do
      expect(Saltbox::Actions.config.list_adapter!).to eq(Saltbox::Actions::Adapters::Lists::Pagy)
      3.times { Event.create!(org_id: 1, title: "Event #{it}") }
      records, pagination = Saltbox::Actions::Adapters::Lists::Pagy.paginate(Event.order(:id), page: 2, page_size: 2)
      expect(records.map(&:title)).to eq(["Event 2"])
      expect(Saltbox::Actions::Adapters::Lists::Pagy.list_meta(pagination, nil))
        .to eq(pagination: {page: 2, page_size: 2, total_items: 3, total_pages: 2, from: 3, to: 3})
    end

    it "asks the app for a table's own methods" do
      expect { Saltbox::Actions::Adapters::Lists::Pagy.filters(Object) }.to raise_error(ArgumentError, /name its list adapter in config.list_adapter/)
    end
  end

  it "keeps no block settings: what an app adds is its base class's" do
    removed = %i[refresh_caller around_invocation check_caller around_perform on_changes on_access_refused
      after_change_commit feature_enabled validate_feature permissions_held schema_user on_forbidden_fields
      map_error error_mappings confirm area_for check_action action_checks check_registry registry_checks]
    expect(removed.select { Saltbox::Actions.config.respond_to?(it) }).to be_empty
    expect { with_fresh_config { |config| config.max_array_items = -> { 5 } } }.to raise_error(ArgumentError, /takes a number, such as 100/)
    expect { with_fresh_config { |config| config.approvals = {user: "User", message: "Ask"} } }.to raise_error(ArgumentError, /message/)
  end
end
