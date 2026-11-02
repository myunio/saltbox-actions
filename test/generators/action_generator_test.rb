require "test_helper"
require "generators/action/action_generator"
require "generators/test_unit/action/action_generator"
require "tmpdir"
require "open3"

class ActionGeneratorTest < ActiveSupport::TestCase
  test "Rails discovers the default test framework hook" do
    assert_equal TestUnit::Generators::ActionGenerator, Rails::Generators.find_by_namespace("test_unit:action")
    Dir.mktmpdir("action-generator") do |destination|
      capture_io do
        Saltbox::Actions::Generators::ActionGenerator.start(["Event::Update", "--no-catalogue"], destination_root: destination)
      end
      test_file = Pathname(destination).join("test/actions/event/update_action_test.rb")
      assert test_file.exist?, "rails g action must invoke test_unit by default"
      assert Pathname(destination).join("app/actions/event/update_action.rb").exist?
      source = test_file.read
      assert_includes source, "self.action_class = Event::UpdateAction"
      assert_includes source, "id: visible_record.id.to_s"
      # Supply this app's records where the template asks for them, then run
      # the generated test through Minitest itself in a separate process.
      source = source.sub('raise NotImplementedError, "a person who may run Event::UpdateAction"',
        "Account.new(id: 1, permissions: %w[events.view events.manage])")
      source = source.sub('raise NotImplementedError, "a record the person can see"',
        'Event.create!(org_id: 1, title: "AGM")')
      test_file.write(source)
      output, status = Open3.capture2e(RbConfig.ruby, "-Itest", "-Ilib", test_file.to_s)
      assert status.success?, output
      assert_match(/1 runs, .*0 failures, 0 errors/, output)
    end
  end

  test "forwards custom verb id options through the Rails hook" do
    [true, false].each do |takes_id|
      Dir.mktmpdir("action-generator") do |destination|
        capture_io do
          Saltbox::Actions::Generators::ActionGenerator.start(
            ["Event::Archive", "--kind=change", "--no-catalogue", (takes_id ? "--id" : "--no-id")],
            destination_root: destination
          )
        end
        source = Pathname(destination).join("test/actions/event/archive_action_test.rb").read
        assert_equal takes_id, source.include?("id: visible_record.id.to_s")
      end
    end
  end

  test "writes a factory-free no-id test and a nested custom verb test" do
    Dir.mktmpdir("action-generator") do |destination|
      capture_io { TestUnit::Generators::ActionGenerator.start(["Event::List"], destination_root: destination) }
      source = Pathname(destination).join("test/actions/event/list_action_test.rb").read
      assert_includes source, "arguments = {}"
      refute_includes source, "visible_record"
      capture_io { TestUnit::Generators::ActionGenerator.start(["Event::Type::Archive"], destination_root: destination) }
      source = Pathname(destination).join("test/actions/event/type/archive_action_test.rb").read
      assert_includes source, "class Event::Type::ArchiveActionTest"
      assert_includes source, "id: visible_record.id.to_s"
      refute_includes source, "FactoryBot"
      capture_io { TestUnit::Generators::ActionGenerator.start(["Event::Archive", "--no-id"], destination_root: destination) }
      source = Pathname(destination).join("test/actions/event/archive_action_test.rb").read
      refute_includes source, "visible_record"
    end
  end
end
