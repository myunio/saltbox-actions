module Saltbox
  module Actions
    # Sets the app's own Current for each call: the class named Current, an
    # ActiveSupport::CurrentAttributes, as Rails apps keep one. The call
    # starts from a fresh Current, with every attribute at its default, so
    # nothing from the request around it, such as a session or a cache,
    # reaches it. Then each of these the app's Current declares is set,
    # through its writer, so a writer that sets more, as Rails's guide shows
    # for user=, runs:
    # - the person, under their model's name: account for an Account;
    # - the tenant, under its model's name: org for an Org;
    # - agent: the agent's stamp (Caller#agent_stamp), nil for the person's own click;
    # - surface, connection and invocation_id.
    # The call runs in the tenant's time zone, when the tenant has one
    # (time_zone). Afterwards, error or not, the attributes the call found
    # are put back as they were, without running any writer, so a writer
    # that sets another attribute (a session= that sets account) cannot
    # undo one restored before it; the time zone the call found is put
    # back too, so a writer that sets Time.zone ends with the call.
    #
    # A system caller (Caller.system) keeps the Current around it, such as
    # a job's. An app without a Current is left alone.
    #
    # @example app/models/current.rb
    #   class Current < ActiveSupport::CurrentAttributes
    #     attribute :user, :agent, :surface
    #   end
    # @api private
    module AppCurrent
      module_function

      # @param caller [Caller] the refreshed caller
      # @param tenant [Object, nil] the call's tenant
      # @param invocation_id [String, nil]
      # @yield the call
      # @return [Object] the block's value
      def set(caller, tenant:, invocation_id:, &)
        return yield if caller.system?
        current = app_current
        return in_zone(tenant, &) unless current
        found = current.instance.attributes
        zone = Time.zone
        begin
          current.instance.attributes = current.new.attributes
          assign(current, caller, tenant, invocation_id)
          in_zone(tenant, &)
        ensure
          current.instance.attributes = found
          Time.zone = zone
        end
      end

      # @return [Class, nil] the app's Current, when it is a CurrentAttributes
      def app_current
        current = Object.const_defined?(:Current) ? Object.const_get(:Current) : nil
        current if current.is_a?(Class) && current < ActiveSupport::CurrentAttributes
      end

      def assign(current, caller, tenant, invocation_id)
        values = {agent: caller.agent_stamp, surface: caller.surface, connection: caller.connection, invocation_id:}
        values[record_attribute(caller.user)] = caller.user
        values[record_attribute(tenant)] = tenant
        values.each { |name, value| current.public_send(:"#{name}=", value) if name && current.defaults.key?(name) }
      end

      def record_attribute(record) = record.class.try(:model_name)&.singular&.to_sym

      def in_zone(tenant, &)
        zone = tenant.try(:time_zone)
        zone ? Time.use_zone(zone, &) : yield
      end
    end
  end
end
