RSpec.describe Saltbox::Actions::Base do
  include ActiveJob::TestHelper

  let(:event) { Event.create!(org_id: 1, title: "AGM") }

  def action(name, &body)
    Class.new(ApplicationAction) do
      define_singleton_method(:name) { name }
      class_eval(&body)
    end
  end

  describe "the member record" do
    it "is loaded before perform through the person's scope, authorized, and kept as the view's instance variable" do
      shown = action("Events::ShowAction") do
        def perform = render(json: {title: event.title, same: event.equal?(@event)})
      end
      expect(run({id: event.id}, as: as_screen(reader), action: shown).body).to eq("title" => "AGM", "same" => true)
      expect { run({id: event.id}, as: as_screen(stranger), action: shown) }.to be_refused.with(:forbidden)
      elsewhere = Event.create!(org_id: 2, title: "Elsewhere")
      expect { run({id: elsewhere.id}, as: as_screen(reader), action: shown) }.to be_not_found
    end

    it "is found with find_<record> when the action's lookup differs, inside the same scope" do
      by_title = action("Events::ShowAction") do
        def perform = render(:show)

        private

        def find_event(events) = events.find_by!(title: id)
      end
      expect(run({id: event.title}, as: as_screen(reader), action: by_title).body.dig("data", "event", "id")).to eq(event.id)
      Event.create!(org_id: 2, title: "Hidden")
      expect { run({id: "Hidden"}, as: as_screen(reader), action: by_title) }.to be_not_found
    end

    it "is not found when find_<record> returns nil" do
      by_title = action("Events::ShowAction") do
        def perform = render(:show)

        private

        def find_event(events) = events.find_by(title: id)
      end
      expect { run({id: "Nothing"}, as: as_screen(reader), action: by_title) }.to be_not_found
    end

    it "keeps a parent's own reader in its subclasses" do
      parent = action("Events::ShowAction") do
        def perform = render(json: {title: event})

        def event = super.title.upcase
      end
      child = Class.new(parent) { define_singleton_method(:name) { "Events::ShowAction" } }
      expect(run({id: event.id}, as: as_screen(reader), action: child).body).to eq("title" => "AGM")
    end
  end

  describe "attributes" do
    it "read a local date and time in the app's time zone, as a datetime column does, in a list too" do
      scheduled = action("Events::ScheduleAction") do
        kind :read
        policy_rule :index?
        attribute :at, :datetime
        attribute :also, :array, of: {at: :datetime}

        def perform
          authorize Event
          skip_policy_scope
          render json: {at: at.iso8601(6), also: also.first["at"].iso8601(6)}
        end
      end
      body = Time.use_zone("America/St_Johns") do
        run({at: "2026-11-02T18:30:12.123456", also: [{at: "2026-11-02T18:30"}]}, as: as_screen(reader), action: scheduled).body
      end
      expect(body).to eq("at" => "2026-11-02T18:30:12.123456-03:30", "also" => "2026-11-02T18:30:00.000000-03:30")
    end

    it "take a callable default that satisfies their presence validation when left out" do
      cancelled = action("Events::CancelAction") do
        attribute :reason, :string, default: -> { "No reason given" }
        validates :reason, presence: true

        def perform = render(json: {reason:})
      end
      expect(run({id: event.id}, as: as_screen(manager), action: cancelled).body).to eq("reason" => "No reason given")
    end
  end

  describe "inherited declarations" do
    it "carry who may run an action, and how, to its subclasses until they declare their own" do
      parent = action("Events::CancelAction") do
        connections :never
        permission "events.manage"
        policy_rule :update?
        featured
        idempotent
      end
      child = Class.new(parent) { define_singleton_method(:name) { "Events::CancelAction" } }
      expect(child).to have_attributes(connections: :never, permissions: ["events.manage"], declared_query: :update?, featured?: true, idempotent?: true)
      child.connections :confirm
      expect([child.connections, parent.connections]).to eq(%i[confirm never])
    end

    it "carry attribute :id and accepts" do
      parent = action("Events::ArchiveAction") do
        kind :change
        attribute :id
        accepts :title
      end
      child = Class.new(parent) { define_singleton_method(:name) { "Events::ArchiveAction" } }
      expect(child).to have_attributes(declares_id?: true, accepted_fields: ["title"])
    end
  end

  describe "validations" do
    let(:reschedule) do
      action("Events::RescheduleAction") do
        kind :change
        attribute :id
        connections :confirm
        policy_rule :update?
        attribute :starts_on, :date
        validate { errors.add(:starts_on, "must be in the future") if starts_on && starts_on < Date.new(2026, 1, 1) }

        def perform
          event.update!(starts_on:)
          render :show
        end
      end
    end

    it "run before confirmation, refused as validation_failed by field, with nothing written" do
      with_settings(enforce_confirm: true) do
        expect { run({id: event.id, starts_on: "2020-01-01"}, as: as_mcp(manager), action: reschedule) }
          .to raise_error(Saltbox::Actions::Error::Invalid) { expect(it.errors).to eq("starts_on" => ["must be in the future"]) }
        expect { run({id: event.id, starts_on: "2027-01-01"}, as: as_mcp(manager), action: reschedule) }.to be_refused.with(:confirmation_required)
      end
      expect(event.reload.starts_on).to be_nil
    end

    it "give a model's errors by field without its name, so a screen can add them back to its record once" do
      error = begin
        run({id: event.id, title: ""}, as: as_screen(manager), action: Events::UpdateAction)
      rescue Saltbox::Actions::Error::Invalid => invalid
        invalid
      end
      expect(error.errors).to eq("title" => ["can't be blank"])
      error.errors.each { |field, messages| messages.each { event.errors.add(field, it) } }
      expect(event.errors.full_messages).to eq(["Title can't be blank"])
    end
  end

  describe "paginated" do
    it "declares page and page_size as attributes, bounded by their validations" do
      listed = action("Events::ExportAction") do
        policy_rule :index?
        paginated per_page: 2, max_per_page: 3

        def perform
          authorize Event
          skip_policy_scope
          render json: {page:, page_size:}
        end
      end
      expect(listed.input_schema["properties"]).to include("page" => {"type" => "integer", "minimum" => 1, "default" => 1},
        "page_size" => {"type" => "integer", "minimum" => 1, "maximum" => 3, "default" => 2})
      expect(run({}, as: as_screen(reader), action: listed).body).to eq("page" => 1, "page_size" => 2)
      expect { run({page_size: 4}, as: as_screen(reader), action: listed) }.to have_field_errors(:page_size)
    end
  end

  describe ".perform_now and .perform_later" do
    it "runs the action now as the caller, through every refusal" do
      result = Events::UpdateAction.perform_now(caller: as_screen(manager), id: event.id, title: "Renamed")
      expect(result.body.dig("data", "event", "title")).to eq("Renamed")
      expect { Events::UpdateAction.perform_now(caller: as_screen(reader), id: event.id, title: "X") }.to be_refused.with(:forbidden)
    end

    it "runs the action later as the same caller, refusing then a caller who may no longer run it" do
      Events::UpdateAction.perform_later(caller: as_mcp(manager), id: event.id, title: "Later")
      expect(enqueued_jobs.size).to eq(1)
      perform_enqueued_jobs
      expect(event.reload.title).to eq("Later")
      expect(event.versions.last).to have_attributes(agent: "RSpec agent", surface: "mcp")

      Events::UpdateAction.perform_later(caller: as_screen(reader), id: event.id, title: "Refused")
      expect { perform_enqueued_jobs }.not_to raise_error
      expect(event.reload.title).to eq("Later")
    end
  end
end
