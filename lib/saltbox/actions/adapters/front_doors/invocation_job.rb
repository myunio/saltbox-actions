require "active_job"

module Saltbox
  module Actions
    module Adapters
      module FrontDoors
        # Runs an action later (Base.perform_later), as the caller who enqueued
        # it, through the same Invocation every surface uses. The caller travels
        # as its fields: the person and the connection as Active Job serializes
        # them (a record as its GlobalID), and its access, which must serialize
        # too. Every refusal runs again when the job runs, so a person who lost
        # access in between is refused; the refusal is logged and the job
        # dropped, never retried, as discard_on does.
        class InvocationJob < ActiveJob::Base
          discard_on Error do |job, error|
            job.logger&.info("#{job.arguments.first} was refused when it ran later: #{error.code}: #{error.message}")
          end

          # Carries SystemUser, Caller.system's default user, to the job.
          # @api private
          class SystemUserSerializer < ActiveJob::Serializers::ObjectSerializer
            # @return [Hash]
            def serialize(_user) = super({})

            # @return [SystemUser]
            def deserialize(_hash) = SystemUser.instance

            # @return [Class]
            def klass = SystemUser
          end
          ActiveJob::Serializers.add_serializers(SystemUserSerializer)

          # @param caller [Caller]
          # @return [Hash] what the job needs to build the caller again
          # @api private
          def self.serialize_caller(caller) = caller.to_h.compact.merge(class: caller.class.name).deep_stringify_keys

          # @param action [String] the action's public name, found in the registry
          # @param input [Hash]
          # @param caller [Hash] from serialize_caller
          # @return [Result]
          # @raise [ArgumentError] when the caller's class is not a Caller
          def perform(action, input, caller)
            caller_class = caller.fetch("class").safe_constantize
            raise ArgumentError, "#{caller["class"]} is not a Saltbox::Actions::Caller" unless caller_class.is_a?(Class) && caller_class <= Caller
            Invocation.call(action: Registry.fetch(action), caller: caller_class.new(**caller.except("class").symbolize_keys), arguments: input)
          end
        end
      end
    end
  end
end
