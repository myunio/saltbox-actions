require "rails/generators"
require "rails/generators/named_base"

module Rspec
  module Generators
    # Writes spec/actions/<resources>/<words>_action_spec.rb for `rails g action`,
    # which reaches it through hook_for :test_framework. The spec runs the
    # action for a person on a screen, and for one that works on a record,
    # checks a record the person cannot see is not found. It assumes no
    # factories and no roles. An app overrides the template at
    # lib/templates/rspec/action/action_spec.rb.tt, to build its people with
    # its own factories.
    class ActionGenerator < ::Rails::Generators::NamedBase
      namespace "rspec:action"
      source_root File.expand_path("templates", __dir__)

      class_option :id, type: :boolean, desc: "Whether the action works on one record named by an id"

      # @return [void]
      def write_spec
        template "action_spec.rb.tt", spec_path
      end

      # @return [void]
      def say_placeholders
        say "Fill in the placeholders in #{spec_path}: it raises NotImplementedError until you do.", :yellow
      end

      private

      def spec_path = File.join("spec/actions", *class_path, "#{file_name}_action_spec.rb")

      def words = file_name.split("_")

      def verb = words.first

      def resource_name = class_path.map(&:camelize).join("::")

      def model = Saltbox::Actions::Naming.model_for(resource_name)

      # @return [String] "an event", "an account"
      def a_record
        noun = model.model_name.human.downcase
        "#{noun.match?(/\A[aeiou]/) ? "an" : "a"} #{noun}"
      end

      def action_class_name = "#{resource_name}::#{words.map(&:camelize).join}Action"

      # What `rails g action` says, then the action's class, then the verb table.
      def takes_id?
        return options[:id] unless options[:id].nil?
        action_class_name.constantize.takes_id?
      rescue NameError
        Saltbox::Actions.config.base.verbs.dig(verb, :member) == true
      end
    end
  end
end
