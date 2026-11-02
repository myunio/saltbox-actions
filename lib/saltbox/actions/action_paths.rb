module Saltbox
  module Actions
    # The folders actions load from, the way I18n.load_path lists locale
    # files: the app's own app/actions, then any folder an engine adds in an
    # initializer.
    #
    # A folder may name a namespace for its actions' public names. It takes
    # the place of an isolated engine's module, so an engine can choose the
    # word agents and scripts see, or keep it when the module is renamed.
    # It is for isolated engines (isolate_namespace): a model in an engine
    # that is not isolated keeps its module in its name, so the namespace
    # would be added to it (list_billing_billing_invoices).
    #
    # @example An engine's actions, named list_billing_invoices
    #   module Billing
    #     class Engine < ::Rails::Engine
    #       isolate_namespace Billing
    #
    #       initializer "billing.actions" do
    #         Saltbox::Actions.config.action_paths.add(root.join("app/actions"), namespace: "billing")
    #       end
    #     end
    #   end
    class ActionPaths
      include Enumerable

      # One folder: its path (relative to Rails.root, or absolute) and the
      # namespace its actions' names take, if any.
      Path = Data.define(:path, :namespace) do
        # @return [Pathname] the folder's full path, the same however it was spelled
        def root = Rails.root.join(path.to_s).cleanpath

        # @param file [String]
        # @return [Boolean] whether the file is inside the folder
        def covers?(file) = file.to_s.start_with?("#{root}/")
      end

      NAMESPACE = /\A[a-z][a-z0-9_]*\z/

      # @param paths [Enumerable<String, Pathname, Path>]
      def initialize(paths = [])
        @paths = []
        paths.each { |path| path.is_a?(Path) ? @paths << path : add(path) }
      end

      # @param path [String, Pathname] relative to Rails.root, or absolute
      # @param namespace [String, Symbol, nil] the word in its actions' names
      #   in place of an isolated engine's module: list_billing_invoices
      # @return [self]
      # @raise [ArgumentError] for a namespace that cannot be part of a name
      def add(path, namespace: nil)
        namespace = namespace&.to_s
        if namespace && !namespace.match?(NAMESPACE)
          raise ArgumentError, "Action path namespace #{namespace.inspect} must be lowercase letters, digits and underscores"
        end
        @paths.reject! { it.path.to_s == path.to_s }
        @paths << Path.new(path:, namespace:)
        self
      end

      # @param path [String, Pathname]
      # @return [self]
      def <<(path) = add(path)

      # @yieldparam path [Path]
      def each(&) = @paths.each(&)

      # @param file [String]
      # @return [Path, nil] the folder holding the file, the deepest when folders nest
      def for(file) = select { it.covers?(file) }.max_by { it.root.to_s.length }

      # @param file [String] a file inside one of the folders
      # @return [Pathname] its path inside its folder: events/update_action.rb
      def relative(file) = Pathname(file).relative_path_from(self.for(file).root)

      # @param action [Class]
      # @return [String, nil] the namespace of the folder its file is in
      def namespace_for(action)
        file = action.name && Object.const_source_location(action.name)&.first
        file && self.for(file)&.namespace
      rescue NameError
        nil
      end

      # @return [String] the folders, for messages
      def to_s = map { it.path.to_s }.join(", ")
    end
  end
end
