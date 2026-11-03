require "rails/generators"
require "rails/generators/named_base"
require "saltbox/actions"

module TestUnit
  module Generators
    class ActionGenerator < ::Rails::Generators::NamedBase
      namespace "test_unit:action"
      source_root File.expand_path("templates", __dir__)

      class_option :member, type: :boolean, default: true

      def write_test
        template "action_test.rb.tt", test_path
      end

      def say_placeholders
        say "Fill in the placeholders in #{test_path}: it raises NotImplementedError until you do.", :yellow
      end

      private

      def test_path = File.join("test/actions", *class_path, "#{file_name}_action_test.rb")

      def action_class_name = "#{class_path.map(&:camelize).join("::")}::#{file_name.camelize}Action"

      def takes_id?
        action_class_name.constantize.takes_id?
      rescue NameError
        entry = Saltbox::Actions.config.base.verbs[file_name.split("_").first]
        entry ? entry[:member] : options[:member]
      end
    end
  end
end
