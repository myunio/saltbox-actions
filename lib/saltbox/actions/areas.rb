module Saltbox
  module Actions
    # The app's areas, from Configuration#areas: the parts of the app a
    # connection is granted and a change is announced to, such as events or
    # members. Each model an action changes belongs to exactly one area, so a
    # change can always be announced; an area's rule may let everyone who
    # reads the area see the record, person and agent of a change to its
    # metadata_models, and names the read action that admits a person.
    #
    # @example config/initializers/saltbox_actions.rb
    #   config.areas = {
    #     "events" => {models: %w[Event Event::Type], metadata_models: %w[Event], read_action: "list_events"},
    #     "documents" => {models: %w[Document Document::Assignment]}
    #   }
    #
    # With areas given, Configuration#area_for answers from them, and
    # `rails actions:check` runs Areas.validate!.
    module Areas
      # The dependent: options that destroy a record's dependents with it.
      DESTROYING = %i[destroy destroy_async].freeze

      class << self
        # @return [Array<String>] every area, in the order the app lists them
        def names = rules.keys

        # @param type [String] a model's name
        # @return [String, nil] the area whose models name it
        def area_for(type) = rules.find { |_area, rule| rule.fetch(:models).include?(type) }&.first

        # @param type [String] a changed model's name
        # @return [String] its area
        # @raise [ArgumentError] when no area maps it
        def for_model!(type) = area_for(type) || raise(ArgumentError, "No area maps #{type}: add it to config.areas")

        # @param area [String]
        # @param type [String] a changed model's name
        # @return [Boolean] whether the area's rule lets its readers see this model's record, person and agent
        def metadata?(area, type) = rules.dig(area, :metadata_models)&.include?(type) || false

        # Whether the caller may read the area: its read action is a read
        # action in that area, listed for the caller. Run it inside
        # Saltbox::Actions.within.
        #
        # @param area [String]
        # @param caller [Caller]
        # @return [Boolean]
        def readable?(area, caller)
          name = rules.dig(area, :read_action) or return false
          action = Registry.actions.find { it.action_name == name }
          !!(action && action.kind == :read && action.area == area && action.listed_for?(caller))
        end

        # Each changed model belongs to exactly one area, and so does every
        # tracked model an area's models destroy with them, at any depth.
        # Run by `rails actions:check`.
        #
        # @return [void]
        # @raise [ArgumentError] naming the models to fix
        def validate!
          models = rules.values.flat_map { it.fetch(:models) }
          twice = models.tally.select { |_, count| count > 1 }.keys
          raise ArgumentError, "config.areas maps #{twice.join(", ")} more than once: a model has exactly one area" if twice.any?
          rules.each do |area, rule|
            stray = rule.fetch(:metadata_models) - rule.fetch(:models)
            raise ArgumentError, "config.areas[#{area.inspect}] names metadata_models it does not map: #{stray.join(", ")}" if stray.any?
          end
          unmapped = models.flat_map { tracked_dependents(it.constantize) }.map(&:name).uniq - models
          raise ArgumentError, "Map #{unmapped.join(", ")} to an area in config.areas: an area's models destroy them" if unmapped.any?
        end

        # @param model [Class<ActiveRecord::Base>]
        # @param seen [Set<Class>] models already walked
        # @return [Array<Class>] tracked models destroyed with +model+, at any depth
        # @api private
        def tracked_dependents(model, seen = Set.new)
          model.reflect_on_all_associations.flat_map do |association|
            next [] unless DESTROYING.include?(association.options[:dependent]) && !association.polymorphic?
            dependent = association.klass
            next [] unless seen.add?(dependent)
            (tracked?(dependent) ? [dependent] : []) + tracked_dependents(dependent, seen)
          end
        end

        # A change to it is noted: it includes ChangeTracking, or PaperTrail
        # versions it while :paper_trail is declared.
        #
        # @param model [Class<ActiveRecord::Base>]
        # @return [Boolean]
        def tracked?(model)
          model.include?(ChangeTracking) || (Adapters.declared?(:paper_trail) && model.respond_to?(:paper_trail_options))
        end

        private

        def rules = Actions.config.areas
      end
    end
  end
end
