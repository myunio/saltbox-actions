module Saltbox
  module Actions
    # Notes each record an action creates, updates or destroys, so
    # Configuration#on_changes and the changes.saltbox_actions notification
    # hear of it. Include it in ApplicationRecord. A write undone by a
    # rollback is not noted; outside an action it does nothing.
    #
    # @example app/models/application_record.rb
    #   class ApplicationRecord < ActiveRecord::Base
    #     primary_abstract_class
    #     include Saltbox::Actions::ChangeTracking
    #   end
    module ChangeTracking
      extend ActiveSupport::Concern

      included do
        after_create { ChangeTracking.note(self, "create") }
        after_update { ChangeTracking.note(self, "update") if saved_changes? }
        after_destroy { ChangeTracking.note(self, "destroy") }
      end

      # @param record [ActiveRecord::Base]
      # @param event [String]
      # @return [void]
      def self.note(record, event)
        Invocation.note(record.class.polymorphic_name, record.id, event, transaction: record.class.current_transaction)
      end
    end
  end
end
