require "digest"
require "json"

module Saltbox
  module Actions
    module Adapters
      module Confirmation
        # A person's approvals of their agents' calls to :confirm actions,
        # kept in the app's own table, for Configuration#confirm. An agent's
        # first call is refused with confirmation_required and left as a
        # request; the person approves it on one of the app's screens; the
        # same call, with the same arguments, from the same connection and
        # surface, then runs once.
        #
        # `rails g actions:approvals` writes the migration and the model,
        # which includes this module. The app adds its own tenancy, the
        # screen that lists a person's requests (#pending), and the
        # controller that approves (#approve!) or declines (destroy) one.
        #
        # A request is saved once the call's writes have rolled back, so a
        # refusal from inside a change (Caller#confirm!) still leaves the
        # person a request to approve.
        #
        # @example app/models/action_approval.rb
        #   class ActionApproval < ApplicationRecord
        #     include Saltbox::Actions::Adapters::Confirmation::Approvals
        #   end
        #
        # @example config/initializers/saltbox_actions.rb
        #   Saltbox::Actions.configure do |config|
        #     config.adapters = [:pundit, :approvals]
        #     config.confirm { |invocation, action| ActionApproval.redeem!(invocation, action) }
        #   end
        module Approvals
          extend ActiveSupport::Concern

          included do
            # The association that holds the person who approves: the
            # caller's user. user by default; an app whose people are
            # accounts sets :account.
            class_attribute :approver, instance_writer: false, default: :user
            # How long a request waits for the person.
            class_attribute :request_lifetime, instance_writer: false, default: 1.hour
            # How long an approval waits for the agent to call again.
            class_attribute :approval_lifetime, instance_writer: false, default: 15.minutes

            validates :surface, :action_name, :confirms, :arguments_digest, :expires_at, presence: true
            validates :arguments, exclusion: {in: [nil]}

            scope :unexpired, -> { where(used_at: nil, expires_at: Time.current..) }
            scope :pending, -> { unexpired.where(approved_at: nil) }
            scope :approved, -> { unexpired.where.not(approved_at: nil) }
          end

          class_methods do
            # The confirm hook: lets the call run when the person approved
            # this exact call, and uses the approval up; otherwise refuses it,
            # carrying the request to approve, which Invocation saves.
            #
            # @param invocation [Invocation] the agent's call
            # @param action [Class] the :confirm action: the call's own, or one Caller#confirm! names
            # @return [true]
            # @raise [Error::ConfirmationRequired] until the person approves
            def redeem!(invocation, action)
              call = matching(invocation, action)
              id = call.approved.pick(primary_key)
              return true if id && call.approved.where(primary_key => id).update_all(used_at: Time.current) == 1
              request = call.pending.first || call.new(agent_name: invocation.caller.agent_name,
                arguments: invocation.arguments.as_json, expires_at: request_lifetime.from_now)
              raise Error::ConfirmationRequired.new(request.refusal_message, details: {"action" => request.confirms}, request:)
            end

            # @param invocation [Invocation]
            # @param action [Class]
            # @return [ActiveRecord::Relation] approvals of this call: the
            #   person, connection, surface, actions and arguments
            def matching(invocation, action)
              caller = invocation.caller
              where("#{approver}_id" => caller.user.id).where(connection_id: caller.connection&.id, surface: caller.surface,
                action_name: invocation.action.action_name, confirms: action.action_name, arguments_digest: digest(invocation.arguments))
            end

            # @param arguments [Hash]
            # @return [String] the same for the same arguments, whatever their order
            def digest(arguments) = Digest::SHA256.hexdigest(JSON.generate(sorted(arguments.as_json)))

            private

            def sorted(value)
              case value
              when Hash then value.sort.to_h { |key, item| [key, sorted(item)] }
              when Array then value.map { sorted(it) }
              else value
              end
            end
          end

          # Approves the request: the agent's same call runs once, within
          # approval_lifetime. Only a request still waiting can be approved.
          #
          # @return [void]
          # @raise [ActiveRecord::RecordNotFound] when the request has expired, or was approved or used
          def approve!
            approved_at = Time.current
            expires_at = approval_lifetime.from_now
            answered = self.class.pending.where(self.class.primary_key => id).update_all(approved_at:, expires_at:, updated_at: approved_at)
            raise ActiveRecord::RecordNotFound.new("This request has expired or was already answered", self.class.name) unless answered == 1
            assign_attributes(approved_at:, expires_at:, updated_at: approved_at)
            clear_changes_information
          end

          # @return [String] the title of the action the person is asked to approve
          def title = Registry.fetch(confirms).title

          # What the agent is told until the person approves. Override it to
          # say where in the app the person approves.
          #
          # @return [String]
          def refusal_message = "#{Error::ConfirmationRequired.new.message} Then call it again with the same arguments."
        end
      end
    end
  end
end
