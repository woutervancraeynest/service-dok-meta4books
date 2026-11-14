require_relative "base"
require_relative "../meta4books/onix_product"

module Tools
  # Filtered product lists and change tracking via the ONIX products API.
  # The API requires either isbns or mutatiedatum; when the agent passes no
  # modified_since we fall back to DEFAULT_MODIFIED_SINCE so other filters work.
  class ListProducts < Base
    DEFAULT_MODIFIED_SINCE = "20000101".freeze
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    MAX_FULL_LIMIT = 25

    PRODUCT_GROUPS = {
      "printbooks" => "papierenboeken",
      "ebooks" => "ebooks",
      "audiobooks" => "luisterboeken",
      "other" => "overigeboeken"
    }.freeze

    STRING_FILTERS = {
      "publisher" => :uitgever,
      "imprint" => :imprint,
      "series" => :series,
      "nurs" => :nurs,
      "distributor" => :distributor
    }.freeze

    LIST_FILTERS = {
      "publisher_ids" => :publisherids,
      "languages" => :taalcode,
      "product_forms" => :productforms,
      "availability" => :availability,
      "thema" => :thema,
      "avi_old" => :aviold,
      "avi_new" => :avinew,
      "fund_codes" => :fundcode,
      "discount_codes" => :asw
    }.freeze

    BOOLEAN_FILTERS = {
      "orderable" => :bestelbaar,
      "sales_restricted" => :salesrestriction,
      "has_description" => :productdescription,
      "has_excerpt" => :productexcerpt
    }.freeze

    def call
      detail = param("detail") == "full" ? "full" : "summary"
      max_limit = detail == "full" ? MAX_FULL_LIMIT : MAX_LIMIT
      query = filters
      modified_since = date_param("modified_since", with_time: true)
      created_since = date_param("created_since", with_time: true)

      if modified_since.nil? && created_since.nil? && query.empty?
        raise InvalidParams, "Provide modified_since, created_since or at least one filter"
      end

      query[:mutatiedatum] = modified_since || DEFAULT_MODIFIED_SINCE
      query[:creatiedatum] = created_since if created_since
      limit = integer_param("limit", default: DEFAULT_LIMIT, min: 1, max: max_limit)
      offset = integer_param("offset", default: 0, min: 0, max: 1_000_000)
      query[:limit] = limit
      query[:offset] = offset

      result = client.products(query)
      products = result.products.map do |node|
        product = Meta4books::OnixProduct.new(node)
        detail == "full" ? product.to_h : product.summary
      end

      {
        products: products,
        count: products.size,
        total: result.total,
        limit: limit,
        offset: offset,
        next_offset: offset + result.raw_count < result.total.to_i ? offset + result.raw_count : nil,
        modified_since_defaulted: modified_since.nil? ? true : nil
      }.compact
    end

    private

    def filters
      query = {}
      STRING_FILTERS.each do |name, key|
        value = param(name)
        query[key] = value.to_s unless value.nil?
      end
      LIST_FILTERS.each do |name, key|
        list = list_param(name)
        query[key] = list.join(",") unless list.empty?
      end
      BOOLEAN_FILTERS.each do |name, key|
        value = boolean_param(name)
        query[key] = value.to_s unless value.nil?
      end

      groups = list_param("product_groups")
      unless groups.empty?
        invalid = groups - PRODUCT_GROUPS.keys
        raise InvalidParams, "Unknown product_groups: #{invalid.join(', ')}. Allowed: #{PRODUCT_GROUPS.keys.join(', ')}" if invalid.any?

        query[:productvormen] = groups.map { |g| PRODUCT_GROUPS[g] }.join(",")
      end

      front_cover = param("front_cover")
      if front_cover
        level = { "any" => 1, "large" => 2 }[front_cover.to_s]
        raise InvalidParams, "front_cover must be 'any' or 'large'" unless level

        query[:productimagefront] = level
      end

      from = date_param("publication_date_from")
      to = date_param("publication_date_to")
      query[:publicatiedatumvan] = from if from
      query[:publicatiedatumtotenmet] = to if to
      until_date = date_param("modified_until", with_time: true)
      query[:lastmodifieduntil] = until_date if until_date
      query
    end
  end
end
