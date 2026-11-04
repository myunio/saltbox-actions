module Saltbox
  module Actions
    # Notes each record an action creates, updates or destroys through
    # callbacks, so the changes.saltbox_actions notification announces it. Include it in ApplicationRecord. A write a
    # savepoint inside the action rolls back is not noted; outside an action
    # it does nothing. Not noted: writes that skip callbacks (update_all,
    # delete_all, insert_all, upsert_all, update_columns, raw SQL), touch,
    # and writes in before_commit or after_commit callbacks, which run after
    # the changes are announced. Note those with Invocation.note.
    #
    # @example app/models/application_record.rb
    #   class ApplicationRecord < ActiveRecord::Base
    #     primary_abstract_class
    #     include Saltbox::Actions::ChangeTracking
    #   end
    module ChangeTracking
      extend ActiveSupport::Concern

      # What a change assertion says when it heard of nothing and nothing notes changes.
      # @api private
      NOT_IN_USE = "Nothing notes changes: include Saltbox::Actions::ChangeTracking in ApplicationRecord, " \
        "or add :paper_trail to config.adapters"

      included do
        ChangeTracking.in_use = true
        after_create { ChangeTracking.note(self, "create") }
        after_update { ChangeTracking.note(self, "update") if saved_changes? }
        after_destroy { ChangeTracking.note(self, "destroy") }
      end

      class << self
        # @api private
        attr_writer :in_use

        # @return [Boolean] whether a model includes it, or PaperTrail's versions are noted
        # @api private
        def in_use? = @in_use || (Adapters.declared?(:paper_trail) && Adapters::Audit::PaperTrail.installed?)
      end

      # @param record [ActiveRecord::Base]
      # @param event [String]
      # @return [void]
      # @api private
      def self.note(record, event)
        Invocation.note(record.class.polymorphic_name, record.id, event, transaction: record.class.current_transaction)
      end
    end
  end
end
