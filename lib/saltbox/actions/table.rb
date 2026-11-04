module Saltbox
  module Actions
    # What a list action that declares a table (Lists) sends agents, declared
    # once on the table itself: its records' summary, and the associations
    # the summary and the view read, loaded with the page. The app's table
    # base class extends it.
    #
    # @example
    #   class ApplicationTable
    #     extend Saltbox::Actions::Table
    #   end
    #
    #   class EventsTable < ApplicationTable
    #     summary :id, :title, kind: ->(event) { event.kind&.name }
    #     includes :kind
    #   end
    #
    #   class Events::ListAction < ApplicationAction
    #     table EventsTable
    #   end
    module Table
      # Declares the table's summary, as an action's summary is declared
      # (Declarations#summary); an action's own still wins. Called with
      # nothing, it returns it, or the parent table's.
      #
      # @param fields [Array<Symbol>] the record's attributes or methods
      # @param computed [Hash{Symbol => #call}] fields computed from the record
      # @return [Summary, nil]
      def summary(*fields, **computed)
        return @summary || (superclass.summary if superclass.respond_to?(:summary)) if fields.empty? && computed.empty?
        @summary = Summary.build(fields, computed)
      end

      # Declares the associations each page loads with its records. Called
      # with nothing, it returns them.
      #
      # @param associations [Array<Symbol, Hash>] as Active Record's includes takes them
      # @return [Array<Symbol, Hash>]
      def includes(*associations)
        return @includes || [] if associations.empty?
        @includes = associations
      end
    end
  end
end
