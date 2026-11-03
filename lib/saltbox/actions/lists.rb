require "json_schemer"

module Saltbox
  module Actions
    # Lists and pages, with the app's own paging and table libraries
    # (Configuration#list_adapter).
    # - `table` gives a list action the search, sort and filters of one of
    #   the app's tables, the same table its screen shows, and its paging;
    # - `table_index` runs them;
    # - `paginate` pages a list that has no table (declare `paginated`).
    #
    # @example
    #   class Events::ListAction < ApplicationAction
    #     table EventsTable
    #
    #     def perform
    #       @events, @table, @pagination = table_index
    #       render :index
    #     end
    #   end
    module Lists
      extend ActiveSupport::Concern

      # The attribute type that holds each filter's JSON type.
      FILTER_TYPES = {"array" => :array, "string" => :string, "object" => :hash}.freeze

      class_methods do
        # Declares the paging inputs, sort, search when the table takes one,
        # and one input per filter, each with the filter's JSON schema.
        #
        # @param table [Object] the app's table, as Configuration#list_adapter knows it
        # @return [void]
        # @api public
        def table(table = nil)
          return @table unless table
          @table = table
          paginated
          adapter = Actions.config.list_adapter!
          attribute :search, :string if adapter.search?(table)
          attribute :sort, :string
          adapter.filters(table).each do |key, schema|
            attribute key, FILTER_TYPES.fetch(schema["type"]), description: schema["description"]
            validates key, inclusion: {in: schema["enum"]}, allow_nil: true if schema["enum"]
          end
          validate :filters_match_table
        end
      end

      private

      # One page of the table's records, with its metadata and the page, as
      # the app's screen gets them. The table does its own scoping.
      #
      # @return [Array(Object, Hash, Object)] the records, the table's metadata and the pagination
      # @raise [ArgumentError] when the action declares no table
      # @api public
      def table_index
        table = self.class.table or raise ArgumentError, "#{self.class.name} declares no table"
        skip_policy_scope
        adapter = Actions.config.list_adapter!
        filters = adapter.filters(table).keys.to_h { [it.to_s, public_send(it)] }.compact
        params = {"search" => (search if respond_to?(:search)), "sort" => sort, "filter" => filters.presence}.compact
        records = paginate(adapter.query(table, user: current_user, params:))
        [records, adapter.metadata(table, user: current_user, params:), @pagination]
      end

      # One page of the collection, from the page and page_size inputs
      # (`paginated`); sets @pagination for the view.
      #
      # @param collection [Object] the records, such as a relation
      # @return [Object] the page's records
      # @api public
      def paginate(collection)
        records, @pagination = Actions.config.list_adapter!.paginate(collection, page:, page_size:)
        records
      end

      # An input holds a filter's kind of value; the shape inside it, such
      # as a date filter's from and to, is checked against the filter's schema.
      def filters_match_table
        Actions.config.list_adapter!.filters(self.class.table).each do |key, schema|
          value = public_send(key)
          errors.add(key, :invalid) unless value.nil? || JSONSchemer.schema(schema).valid?(value.as_json)
        end
      end
    end
  end
end
