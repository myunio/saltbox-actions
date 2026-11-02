require "rails/generators"
require "rails/generators/named_base"

module Rspec
  module Generators
    # Writes spec/actions/<model>/<words>_action_spec.rb for `rails g action`,
    # which reaches it through hook_for :test_framework. The spec runs the
    # gem's refusal ladder and one example of the action's own. An app
    # overrides the template at lib/templates/rspec/action/action_spec.rb.tt,
    # to build its people with its own factories.
    class ActionGenerator < ::Rails::Generators::NamedBase
      namespace "rspec:action"
      source_root File.expand_path("templates", __dir__)

      # @return [void]
      def write_spec
        template "action_spec.rb.tt", File.join("spec/actions", *class_path, "#{file_name}_action_spec.rb")
      end

      private

      def words = file_name.split("_")

      def verb = words.first

      def model_name = class_path.map(&:camelize).join("::")

      def model = model_name.constantize

      # @return [String] "an event", "an account"
      def a_record
        noun = model.model_name.human.downcase
        "#{noun.match?(/\A[aeiou]/) ? "an" : "a"} #{noun}"
      end

      def action_class_name = "#{model_name}::#{words.map(&:camelize).join}Action"

      # The new action reads it from its class; a verb in the table says it otherwise.
      def takes_id?
        action_class_name.constantize.takes_id?
      rescue NameError
        Saltbox::Actions::Naming::VERBS.dig(verb, :id) == true
      end
    end
  end
end
