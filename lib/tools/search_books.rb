require_relative "base"
require_relative "../meta4books/search_result"

module Tools
  # Free-text search via the Boekenbank JSON search API (/api/zoek).
  class SearchBooks < Base
    FIELDS = %w[gtin13 title authors publisher_name imprint].freeze
    PRODUCT_GROUPS = %w[printbooks ebooks audiobooks other].freeze
    SORT_FIELDS = %w[relevance publication_date publisher_name gtin13].freeze
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 100

    def call
      query = build_query
      limit = query[:limit]
      offset = query[:offset]
      response = client.search(query)
      records = Array(response["data"])

      {
        results: records.map { |record| Meta4books::SearchResult.new(record).to_h },
        total: response["total"],
        limit: limit,
        offset: offset,
        next_offset: next_offset(response["total"], offset, limit),
        hint: "Use get_book or get_books for full details (description, large covers, excerpt, all prices)."
      }.compact
    end

    private

    def build_query
      query = {}
      terms = param("query")
      if terms
        raise InvalidParams, "query must be at least 4 characters" if terms.length < 4

        query[:search_terms] = terms
      end

      fields = list_param("fields")
      unless fields.empty?
        invalid = fields - FIELDS
        raise InvalidParams, "Unknown fields: #{invalid.join(', ')}. Allowed: #{FIELDS.join(', ')}" if invalid.any?

        query[:search_fields] = fields.join(",")
      end

      groups = list_param("product_groups")
      unless groups.empty?
        invalid = groups - PRODUCT_GROUPS
        raise InvalidParams, "Unknown product_groups: #{invalid.join(', ')}. Allowed: #{PRODUCT_GROUPS.join(', ')}" if invalid.any?

        query[:product_form_groups] = groups.join(",")
      end

      add_list(query, :nurs, "nurs")
      add_list(query, :language, "languages")
      add(query, :publication_date_from, date_param("publication_date_from"))
      add(query, :publication_date_to, date_param("publication_date_to"))
      add(query, :createdfrom, date_param("created_from", with_time: true))
      add(query, :createduntil, date_param("created_until", with_time: true))
      fixed_price = boolean_param("fixed_price_active")
      add(query, :priceRegulatedActivated, fixed_price.to_s) unless fixed_price.nil?

      raise InvalidParams, "Provide a query or at least one filter" if query.empty?

      sort = param("sort_by")
      if sort && sort != "relevance"
        raise InvalidParams, "sort_by must be one of: #{SORT_FIELDS.join(', ')}" unless SORT_FIELDS.include?(sort)

        direction = param("sort_direction") == "asc" ? "asc" : "desc"
        query[:sort] = "#{sort},#{direction}"
      end

      query[:send_prices] = boolean_param("include_prices") == false ? "false" : "true"
      query[:limit] = integer_param("limit", default: DEFAULT_LIMIT, min: 1, max: MAX_LIMIT)
      query[:offset] = integer_param("offset", default: 0, min: 0, max: 1_000_000)
      query
    end

    def add(query, key, value)
      query[key] = value unless value.nil?
    end

    def add_list(query, key, name)
      list = list_param(name)
      query[key] = list.join(",") unless list.empty?
    end

    def next_offset(total, offset, limit)
      return nil unless total.is_a?(Integer)

      offset + limit < total ? offset + limit : nil
    end
  end
end
