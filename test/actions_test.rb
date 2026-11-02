require "test_helper"
require "tmpdir"

class ActionsTest < ActiveSupport::TestCase
  include Saltbox::Actions::TestHelper

  self.action_class = Events::UpdateAction

  setup do
    @manager = Account.new(id: 1, permissions: %w[events.view events.manage events.delete])
    @reader = Account.new(id: 2, permissions: %w[events.view])
    @event = Event.create!(org_id: 1, title: "AGM")
  end

  test "loads without RSpec" do
    refute defined?(RSpec)
  end

  test "builds each caller and read-only scopes" do
    {as_screen: "screen", as_webmcp: "webmcp", as_api: "api", as_mcp: "mcp", as_assistant: "assistant"}.each do |helper, surface|
      caller = public_send(helper, @manager)
      assert_equal surface, caller.surface
      assert_equal @manager, caller.account
    end
    assert_equal [Saltbox::Actions.config.scopes.fetch(:read)], as_read_only(@manager).scopes
    assert_equal [], as_mcp(@manager, scopes: []).scopes
    assert_equal "Test agent", as_mcp(@manager).agent
  end

  test "builds the system caller, which the policy decides for" do
    assert as_system.system?
    assert_equal Saltbox::Actions::SystemAccount.instance, as_system.account
    assert_equal @manager, as_system(@manager).account
    assert_equal "Renamed", run({id: @event.id.to_s, title: "Renamed"}, as: as_system).body.dig("data", "event", "title")
    assert_refused(:forbidden) { run({id: @event.id.to_s}, as: as_system, action: Events::DeleteAction) }
  end

  test "custom caller factories run in the test context with default and explicit scopes" do
    original = Saltbox::Actions::TestHelper.config
    Saltbox::Actions::TestHelper.instance_variable_set(:@config, Saltbox::Actions::Testing::Configuration.new)
    Saltbox::Actions::TestHelper.configure do |config|
      config.caller_for(:screen) { |account| ApplicationAction::Caller.screen(account || @manager) }
      config.caller_for(:mcp) { |account, scopes:| ApplicationAction::Caller.new(account:, surface: "mcp", scopes:, agent: @event.title) }
    end
    assert_equal @manager, as_screen(nil).account
    assert_equal "AGM", as_mcp(@manager).agent
    assert_equal Saltbox::Actions.config.scopes.values, as_mcp(@manager).scopes
    assert_equal [], as_mcp(@manager, scopes: []).scopes
    assert_equal "api", as_api(@manager).surface
  ensure
    Saltbox::Actions::TestHelper.instance_variable_set(:@config, original)
  end

  test "runs the configured action and an explicit class or name" do
    result = run({id: @event.id.to_s, title: "Annual meeting"}, as: as_screen(@manager))
    assert_equal "Annual meeting", result.body.dig("data", "event", "title")
    assert_equal "Annual meeting", @event.reload.title
    [WhoamiAction, "whoami"].each do |action|
      assert_equal 1, run(as: as_api(@manager), action:).body.dig("data", "account_id")
    end
    self.class.action_class = nil
    assert_raises(ArgumentError) { run(as: as_screen(@manager)) }
  ensure
    self.class.action_class = Events::UpdateAction
  end

  test "checks refusal codes without hiding unexpected errors" do
    arguments = {id: @event.id.to_s}
    error = assert_refused(:forbidden) { run(arguments, as: as_screen(@reader)) }
    assert_equal "forbidden", error.code
    assert_refused(:insufficient_scope) { run(arguments, as: as_read_only(@manager)) }
    assert_refused(:human_required) { run(arguments, as: as_mcp(@manager), action: Events::ShowNotesAction) }
    assert_raises(Minitest::Assertion) { assert_refused(:not_found) { raise Saltbox::Actions::Error::Forbidden } }
    assert_raises(Minitest::Assertion) { assert_refused { :success } }
    failure = assert_raises(Minitest::Assertion) { assert_refused { raise "bug" } }
    assert_includes failure.message, "bug"
  end

  test "runs each allowed surface and refuses each agent on a human-only action" do
    %i[as_screen as_api as_mcp as_assistant as_webmcp].each do |helper|
      result = run({id: @event.id.to_s}, as: public_send(helper, @manager))
      assert_equal 200, result.status
      next if helper == :as_screen
      assert_refused(:human_required) do
        run({id: @event.id.to_s}, as: public_send(helper, @manager), action: Events::ShowNotesAction)
      end
    end
    assert_equal 200, run({id: @event.id.to_s}, as: as_read_only(@manager), action: Events::ShowAction).status
    assert_refused(:human_required) do
      run({id: @event.id.to_s}, as: as_webmcp(@manager), action: Events::DeleteAction)
    end
  end

  test "hides records from another organization" do
    hidden = Event.create!(org_id: 2, title: "Other team")
    assert_refused(:not_found) { run({id: hidden.id.to_s}, as: as_screen(@manager)) }
  end

  test "checks field errors and raw input schemas" do
    assert_field_errors(:notes) { run({id: @event.id.to_s, notes: "secret"}, as: as_screen(@manager)) }
    assert_invalid_against_schema({id: @event.id.to_s, capacity: "lots"})
    assert_raises(Minitest::Assertion) { assert_invalid_against_schema({id: @event.id.to_s}) }
    assert_raises(Minitest::Assertion) { assert_field_errors(:title) { raise Saltbox::Actions::Error::Forbidden } }
    assert_raises(Minitest::Assertion) { assert_field_errors(:title) { :success } }
  end

  test "checks output schemas and rejects missing schemas" do
    schema = {type: "object", required: ["title"], properties: {title: {type: "string"}}}
    assert_matches_output_schema({title: "AGM"}, schema:)
    result = run({id: @event.id.to_s}, as: as_screen(@manager))
    assert_matches_output_schema(result, schema: {type: "object", required: ["data"]})
    assert_raises(Minitest::Assertion) { assert_matches_output_schema({title: 7}, schema:) }
    assert_raises(ArgumentError) { assert_matches_output_schema({}, schema: nil) }
  end

  test "checks listing and run permission" do
    assert_runnable_by as_mcp(@manager)
    assert_listed_for as_api(@manager)
    assert_raises(Minitest::Assertion) { assert_runnable_by as_read_only(@manager) }
    assert_raises(Minitest::Assertion) { assert_listed_for as_api(@reader) }
    assert_listed_for as_mcp(@manager), action: Events::DeleteAction
    assert_raises(Minitest::Assertion) { assert_runnable_by as_assistant(@manager), action: Events::DeleteAction }
  end

  test "checks audit attribution and change announcements" do
    assert_changes_audit_trail(on: @event, by: @manager, agent: "Test agent", surface: "mcp") do
      assert_announces_changes(@event => :update, Event => :update) do
        run({id: @event.id.to_s, title: "New title"}, as: as_mcp(@manager))
      end
    end
    assert_raises(Minitest::Assertion) { assert_changes_audit_trail(on: @event) {} }
    assert_raises(Minitest::Assertion) { assert_announces_changes(@event => :update) {} }
    assert_raises(Minitest::Assertion) { assert_announces_changes {} }
  end

  test "checks the committed catalogue and all registry promises" do
    assert_matches_catalogue
    Dir.mktmpdir("action-tests") do |directory|
      Saltbox::Actions::Registry.action_files.each do |file|
        relative = Saltbox::Actions.config.action_paths.relative(file).sub_ext("_test.rb")
        path = Pathname(directory).join(relative)
        FileUtils.mkdir_p(path.dirname)
        path.write("")
      end
      assert_valid_action_registry(test_root: directory)
      FileUtils.rm_f(Pathname(directory).join("whoami_action_test.rb"))
      assert_raises(Minitest::Assertion) { assert_valid_action_registry(test_root: directory) }
    end
  end

  test "catalogue check fails on a missing or stale file" do
    original = Saltbox::Actions.config.catalogue_path
    Dir.mktmpdir("catalogue") do |directory|
      Saltbox::Actions.config.catalogue_path = File.join(directory, "actions.json")
      assert_raises(Minitest::Assertion) { assert_matches_catalogue }
      Pathname(Saltbox::Actions.config.catalogue_path).write("[]")
      assert_raises(Minitest::Assertion) { assert_matches_catalogue }
    end
  ensure
    Saltbox::Actions.config.catalogue_path = original
  end
end
