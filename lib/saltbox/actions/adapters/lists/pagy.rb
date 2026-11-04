require "pagy"

module Saltbox
  module Actions
    module Adapters
      module Lists
        # Pages lists with Pagy. It is the list adapter (Configuration#list_adapter)
        # unless the app names its own, and an app's own may extend it for
        # its paging and add a table's methods:
        #
        #   module TableAdapter
        #     extend Saltbox::Actions::Adapters::Lists::Pagy
        #
        #     def self.filters(table) = table.filters
        #     # search?, query and metadata, as Configuration#list_adapter= lists them
        #   end
        #
        # page_size and max_page_size default to Pagy's limit and client_limit
        # (100 when client_limit is unset). Pagy is passed the page and the
        # page size the action has already checked, so they hold whether or not
        # the app sets client_limit. Each list's meta.pagination has page,
        # page_size, total_items, total_pages, from and to.
        #
        # @example config/initializers/saltbox_actions.rb
        #   config.adapters = [:pundit, :pagy]
        module Pagy
          include ::Pagy::Method
          extend self

          # @return [Integer] Pagy's limit
          def self.page_size = ::Pagy::OPTIONS[:limit] || ::Pagy::DEFAULT[:limit]

          # @return [Integer] Pagy's client_limit, or 100 when it is unset
          def self.max_page_size = ::Pagy::OPTIONS[:client_limit] || ::Pagy::DEFAULT[:client_limit] || 100

          # @param collection [ActiveRecord::Relation, Array]
          # @param page [Integer]
          # @param page_size [Integer]
          # @return [Array(Object, ::Pagy)] the page's records and the page
          def paginate(collection, page:, page_size:)
            pagination, records = pagy(:offset, collection, page:, limit: page_size, request: {base_url: "", path: "", params: {}})
            [records, pagination]
          end

          # @param pagination [::Pagy]
          # @param _metadata [Hash, nil] a table's metadata, which an adapter that extends this one adds
          # @return [Hash] meta.pagination
          def list_meta(pagination, _metadata)
            {pagination: {page: pagination.page, page_size: pagination.limit, total_items: pagination.count,
                          total_pages: pagination.pages, from: pagination.from, to: pagination.to}}
          end

          # A list with a table needs the app's own table methods.
          %i[filters search? query metadata].each do |name|
            define_method(name) do |*, **|
              raise ArgumentError, "A table's #{name} comes from the app: name its list adapter in config.list_adapter, " \
                "extending Saltbox::Actions::Adapters::Lists::Pagy for its paging"
            end
          end
        end
      end
    end
  end
end
