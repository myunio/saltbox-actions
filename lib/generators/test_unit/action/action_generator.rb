require "rails/generators"
require "rails/generators/named_base"
require "saltbox/actions"

module TestUnit
  module Generators
    class ActionGenerator < ::Rails::Generators::NamedBase
      namespace "test_unit:action"
      source_root File.expand_path("templates", __dir__)

      class_option :id, type: :boolean, default: true

      def write_test
        template "action_test.rb.tt", File.join("test/actions", *class_path, "#{file_name}_action_test.rb")
      end

      private

      def action_class_name = "#{class_path.map(&:camelize).join("::")}::#{file_name.camelize}Action"

      def takes_id?
        action_class_name.constantize.takes_id?
      rescue NameError
        entry = Saltbox::Actions::Naming::VERBS[file_name.split("_").first]
        entry ? entry[:id] : options[:id]
      end
    end
  end
end
