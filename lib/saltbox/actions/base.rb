module Saltbox
  module Actions
    # The class an app's ApplicationAction inherits from. An action works
    # like a controller action: #perform loads the record through its policy
    # scope, calls authorize, does the work, then renders a view with render
    # or head.
    #
    # Most settings come from the class name: Event::UpdateAction works on
    # Event, asks the policy's update? rule and is the MCP tool update_event.
    # Settings the name cannot give are declared at the top of the class.
    #
    # Each part lives in its own module, the way ActionController::Base is
    # built from modules:
    # - Naming: what the class name gives;
    # - Declarations: what the class declares;
    # - Catalogue: who sees the action in the actions list;
    # - Schema: the JSON Schema of the action's input;
    # - Rendering: render and head;
    # - Permitting: permitted_attributes;
    # - Authorization::None, until the app includes an adapter.
    #
    # The gem's classes are reachable through the app's base class too
    # (ApplicationAction::Error::NotFound, ApplicationAction::Invocation),
    # so app code names its own class, not the gem.
    class Base
      include Naming
      include Declarations
      include Catalogue
      include Schema
      include Rendering
      include Permitting
      include Authorization::None

      Caller = Actions::Caller
      Error = Actions::Error
      Result = Actions::Result
      Params = Actions::Params
      Arguments = Actions::Arguments
      Invocation = Actions::Invocation
      Registry = Actions::Registry
      FrontDoor = Actions::FrontDoor
      Finder = Actions::Finder
      Naming = Actions::Naming
      Declarations = Actions::Declarations
      Schema = Actions::Schema
      Catalogue = Actions::Catalogue
      Rendering = Actions::Rendering
      Permitting = Actions::Permitting

      # @return [Caller] who is calling, and from where
      attr_reader :actor
      # @return [Params] the checked input
      attr_reader :params

      # @param actor [Caller]
      # @param params [Params] the input, already checked against the action's JSON Schema
      def initialize(actor:, params:)
        @actor = actor
        @params = params
      end

      # @return [Object] the person the action acts for
      def account = actor.account

      # Runs #perform, then checks that it called authorize and policy_scope,
      # as Pundit's verify_authorized and verify_policy_scoped do after every
      # controller action.
      #
      # @return [Result] the response #perform rendered, or a 204 when it rendered nothing
      def perform_now
        perform
        verify_authorized
        verify_policy_scoped
        result
      end

      # Does the action's work. Every action defines it.
      #
      # @raise [NotImplementedError] when the action does not define it
      def perform = raise(NotImplementedError, "#{self.class.name} must define perform")
    end
  end
end
