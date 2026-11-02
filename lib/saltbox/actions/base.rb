module Saltbox
  module Actions
    # The class an app's ApplicationAction inherits from. An action is an
    # Active Model object that works like a controller action: its attributes
    # are its input, #perform does the work, then renders a view with render
    # or head.
    #
    # Most settings come from the class name, the way a controller's do:
    # Events::UpdateAction works on Event, asks the policy's update? rule and
    # is the MCP tool update_event. Its verb, update, says the rest: a change,
    # on one record, that is safe to repeat and agents may run. Settings the
    # name and the verb cannot give are declared at the top of the class.
    #
    # Each part lives in its own module, the way ActionController::Base is
    # built from modules:
    # - Naming: what the class name and the verb table give;
    # - Declarations: what the class declares;
    # - Inputs: its attributes and validations;
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
      include Inputs
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
      Inputs = Actions::Inputs
      Schema = Actions::Schema
      Catalogue = Actions::Catalogue
      Rendering = Actions::Rendering
      Permitting = Actions::Permitting

      class << self
        # Runs the action now as the caller, through the same path every
        # surface uses, as Active Job's perform_now runs a job: from a
        # controller, a console or another job.
        #
        # @param caller [Caller]
        # @param input [Hash] the input, as a client would send it
        # @return [Result]
        # @raise [Error]
        #
        # @example From a controller
        #   caller = ApplicationAction::Caller.screen(Current.user)
        #   result = Events::UpdateAction.perform_now(caller:, id: @event.id, title: "AGM")
        def perform_now(caller:, **input) = Invocation.call(name: self, caller:, arguments: input)

        # Runs the action later, as an Active Job (InvocationJob), as the same
        # caller. Every refusal runs again when the job runs, so a person who
        # lost access in between is refused; the refusal is logged and the
        # job dropped, never retried. The caller and the input must be what
        # Active Job can serialize: records, plain values and hashes.
        #
        # @param caller [Caller]
        # @param input [Hash]
        # @return [InvocationJob, false] the enqueued job, or false when enqueuing failed
        def perform_later(caller:, **input)
          InvocationJob.perform_later(name, input.deep_stringify_keys, InvocationJob.serialize_caller(caller))
        end

        # The name of the method that reads a member action's record: event
        # for Event, invoice for an isolated engine's Billing::Invoice.
        #
        # @return [String, nil] nil for an action that works on no one record
        def record_name
          model.model_name.param_key if takes_id? && model.is_a?(Class) && model < ActiveRecord::Base
        end

        # Defines the member record's reader the first time the action is
        # built, once its model is known. It lives in a module of its own, as
        # Active Model's attribute methods do, so the action may override it.
        #
        # @return [void]
        def define_record_reader
          return if @record_reader_defined
          @record_reader_defined = true
          reader = record_name
          return if reader.nil?
          include(Module.new { define_method(reader) { member_record } })
        end
      end

      # @return [Caller] who is calling, and from where
      attr_reader :actor
      # @return [Params] the checked input
      attr_reader :params

      # @param actor [Caller]
      # @param params [Params] the input, already checked against the action's JSON Schema;
      #   each attribute is cast once, by its type, from its value here
      def initialize(actor:, params:)
        @actor = actor
        @params = params
        self.class.define_record_reader
        super(params.to_h.slice(*self.class.declared_attributes.keys))
      end

      # @return [Object] the person the action acts for
      def account = actor.account

      # @return [Object, nil] the id the caller sent, for a member action
      def id = self.class.takes_id? ? params[:id] : nil

      # Loads a member action's record, runs #perform, then checks that it
      # called authorize and policy_scope, as Pundit's verify_authorized and
      # verify_policy_scoped do after every controller action. A list action
      # needs only policy_scope, as a controller's index does: whether the
      # person may list at all was asked before #perform (see
      # Catalogue#permitted?).
      #
      # @return [Result] the response #perform rendered, or a 204 when it rendered nothing
      def perform_now
        member_record if self.class.record_name
        perform
        verify_authorized unless self.class.verb == "list"
        verify_policy_scoped
        result
      end

      # Does the action's work. Every action defines it.
      #
      # @raise [NotImplementedError] when the action does not define it
      def perform = raise(NotImplementedError, "#{self.class.name} must define perform")

      private

      # A member action's record, loaded before #perform the way CanCanCan's
      # load_and_authorize_resource loads a controller's: found through the
      # person's policy scope by the id sent, authorized with the action's
      # rule, and set as the view's instance variable (@event), so
      # `render :show` draws it. An action whose lookup differs defines
      # find_<record>(scope), such as find_event(events); the scope and the
      # authorization still apply.
      #
      # @return [ActiveRecord::Base]
      def member_record
        return @_member_record if defined?(@_member_record)
        name = self.class.record_name
        finder = :"find_#{name}"
        scope = policy_scope(self.class.model)
        record = respond_to?(finder, true) ? send(finder, scope) : scope.find(id)
        authorize(record)
        instance_variable_set(:"@#{name}", record)
        @_member_record = record
      end
    end
  end
end
