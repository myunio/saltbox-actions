module Saltbox
  module Actions
    # Notes each record an action creates, updates or destroys through
    # callbacks, so Configuration#on_changes and the changes.saltbox_actions
    # notification hear of it. Include it in ApplicationRecord. A write a
    # savepoint inside the action rolls back is not noted; outside an action
    # it does nothing. Not noted: writes that skip callbacks (update_all,
    # delete_all, insert_all, upsert_all, update_columns, raw SQL), touch,
    # and writes in before_commit or after_commit callbacks, which run after
    # on_changes. Note those with Invocation.note.
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
