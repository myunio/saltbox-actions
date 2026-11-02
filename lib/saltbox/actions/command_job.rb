require "active_job"

module Saltbox
  module Actions
    # Runs a command later (Command.perform_later), as the caller who
    # scheduled it: the person as a GlobalID, the surface, the agent, the
    # token's scopes and the connection. The refusals run again when the job
    # runs, so a person who lost access in between is refused. A refusal is
    # logged and the job dropped, never retried.
    #
    # The caller's access (what a connection may reach) is not carried: the
    # app's Caller#refresh!, run inside around_invocation, rebuilds it from
    # the connection.
    class CommandJob < ActiveJob::Base
      # @param caller [Caller]
      # @return [Hash] what the job needs to build the caller again
      def self.serialize_caller(caller)
        {"class" => caller.class.name, "account" => caller.account, "surface" => caller.surface, "agent" => caller.agent,
         "scopes" => caller.scopes, "connection" => caller.connection, "credential_id" => caller.credential_id}
      end

      # @param command [String] the command's class name
      # @param arguments [Hash]
      # @param caller [Hash] from serialize_caller
      # @return [Result, nil] nil when refused
      def perform(command, arguments, caller)
        caller = caller.dup
        caller_class = caller.delete("class").constantize
        Invocation.call(name: command.constantize, caller: caller_class.new(**caller.symbolize_keys), arguments:)
      rescue Error => error
        logger.info("#{command} was refused later: #{error.code} #{error.message}")
        nil
      end
    end
  end
end
