RSpec.describe Saltbox::Actions::Command do
  let(:event) { Event.create!(org_id: 1, title: "AGM", starts_on: Date.new(2026, 5, 1)) }
  let(:invoke) { ->(name, arguments, caller) { Saltbox::Actions::Invocation.call(name:, caller:, arguments:) } }

  describe "names" do
    it "takes its model from its namespace, singular, and its public names as an action's" do
      expect(Events::PostponeCommand.model).to eq(Event)
      expect(Events::PostponeCommand.action_name).to eq("postpone_event")
      expect(Events::ExportCommand.action_name).to eq("export_events")
      expect(Events::PostponeCommand.cli_command).to eq(%w[events postpone])
      expect(Events::ArchiveCommand.title).to eq("Archive an event")
      expect(Events::PostponeCommand.title).to eq("Postpone event")
    end

    it "reads kind, id and idempotence from the app's verbs, and its own declarations" do
      expect(Events::PostponeCommand).to have_attributes(kind: :change, takes_id?: true, idempotent?: true)
      expect(Events::ArchiveCommand).to have_attributes(kind: :destructive, takes_id?: true, idempotent?: false)
      expect(Events::ExportCommand).to have_attributes(kind: :read, takes_id?: false, idempotent?: false, policy_query: :index?)
    end

    it "lets agents run a read or a change, and asks first for a destructive one, unless it declares otherwise" do
      expect(Events::PostponeCommand.connections).to eq(:allowed)
      expect(Events::ExportCommand.connections).to eq(:allowed)
      expect(Events::ArchiveCommand.connections).to eq(:confirm)
      command = Class.new(ApplicationCommand) { agents :never }
      expect(command.connections).to eq(:never)
    end

    it "keeps an app's verbs to its own base class" do
      expect(Saltbox::Actions::Command.verb_table).not_to have_key("postpone")
      expect { ApplicationCommand.verb(:fly) }.to raise_error(ArgumentError, /needs kind:/)
    end

    it "is found in app/commands beside the actions, without its abstract base" do
      names = Saltbox::Actions::Registry.actions
      expect(names).to include(Events::PostponeCommand, Events::ExportCommand, Event::UpdateAction)
      expect(names).not_to include(ApplicationCommand)
    end
  end

  describe "input" do
    it "derives the schema from attributes and their validations" do
      schema = Events::PostponeCommand.input_schema
      expect(schema["required"]).to eq(%w[id starts_on])
      expect(schema["properties"]["starts_on"]).to eq("type" => "string", "format" => "date", "description" => "The new day")
      expect(schema["properties"]["reason"]).to eq("type" => "string", "description" => "Why it moved.")
      expect(Events::ExportCommand.input_schema["properties"]["status"]).to include("enum" => Event.statuses.keys)
    end

    it "prefers an attribute's own description to the shared one" do
      command = Class.new(ApplicationCommand) do
        def self.name = "Events::ShowAgendaCommand"
        attribute :id, :string, description: "The agenda's event"
      end
      expect(command.field_description("id")).to be_nil
      expect(Events::ArchiveCommand.field_description("id")).to eq("The record's id.")
    end

    it "takes the fields it accepts, typed from the model's columns, whoever calls" do
      properties = Events::RenameCommand.input_schema(as_screen(manager))["properties"]
      expect(properties.keys).to eq(%w[id title notes parent])
      expect(properties["title"]).to include("type" => "string", "maxLength" => 120, "description" => "The event's name.")
    end
  end

  describe "running" do
    it "runs through the same refusals as an action" do
      expect { invoke.call("archive_event", {id: event.id}, as_mcp(manager)) }.not_to raise_error
      expect { Events::PostponeCommand.perform_now(caller: as_read_only(manager), id: event.id, starts_on: "2026-06-01") }
        .to be_refused.with(:insufficient_scope)
    end

    it "runs now by class" do
      result = Events::ExportCommand.perform_now(caller: as_screen(manager), status: "draft")
      expect(result.body).to eq("count" => 0)
      event
      expect(Events::ExportCommand.perform_now(caller: as_screen(manager)).body).to eq("count" => 1)
    end

    it "runs later as the same caller, refused then if they lost access" do
      job = Saltbox::Actions::CommandJob
      caller = job.serialize_caller(as_mcp(manager))
      job.perform_now("Events::PostponeCommand", {"id" => event.id, "starts_on" => "2026-06-01"}, caller)
      expect(event.reload.starts_on).to eq(Date.new(2026, 6, 1))
      refused = job.serialize_caller(as_mcp(reader))
      expect(job.perform_now("Events::PostponeCommand", {"id" => event.id, "starts_on" => "2026-07-01"}, refused)).to be_nil
      expect(event.reload.starts_on).to eq(Date.new(2026, 6, 1))
    end

    it "enqueues a job carrying the command, its input and the caller" do
      allow(Saltbox::Actions::CommandJob).to receive(:perform_later)
      Events::PostponeCommand.perform_later(caller: as_mcp(manager), id: 1, starts_on: "2026-06-01")
      expect(Saltbox::Actions::CommandJob).to have_received(:perform_later)
        .with("Events::PostponeCommand", {"id" => 1, "starts_on" => "2026-06-01"}, hash_including("surface" => "mcp", "account" => manager))
    end
  end
end
