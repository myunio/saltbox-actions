require "active_job"

module Saltbox
  module Actions
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

      # @param caller [Caller]
      # @return [Hash] what the job needs to build the caller again
      def self.serialize_caller(caller) = caller.to_h.compact.merge(class: caller.class.name).deep_stringify_keys

      # @param action [String] the action's class name
      # @param input [Hash]
      # @param caller [Hash] from serialize_caller
      # @return [Result]
      def perform(action, input, caller)
        fields = caller.except("class").symbolize_keys
        Invocation.call(name: action.constantize, caller: caller.fetch("class").constantize.new(**fields), arguments: input)
      end
    end
  end
end
