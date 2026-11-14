require_relative "codes"
require_relative "prices"

module Meta4books
  # Normalizes one record of the Boekenbank JSON search API (/api/zoek).
  class SearchResult
    def initialize(data, today: Date.today)
      @data = data
      @today = today
    end

    def to_h
      {
        isbn: @data["gtin13"],
        title: @data["title"],
        subtitle: @data["subtitle"],
        part_title: @data["partTitle"],
        section_title: @data["sectionTitle"],
        original_title: @data["originalTitle"],
        contributors: contributors,
        display_publisher: presence(@data["imprint"]) || @data["publisher"],
        publisher: @data["publisher"],
        imprint: presence(@data["imprint"]),
        series: series,
        product_form: product_form,
        languages: Array(@data["languages"]).map { |l| l["code"] },
        nur: @data.dig("nur", "code"),
        thema: Array(@data["themas"]).map { |t| t["code"] },
        avi_new: Array(@data["aviLevelsNew"]).map { |a| a["code"] },
        avi_old: Array(@data["aviLevelsOld"]).map { |a| a["code"] },
        pages: @data["numPages"],
        publication_date: date(@data["isbnFirstPublished"]),
        availability: availability,
        price: price,
        nstc: @data["nstc"],
        front_cover_thumbnail_url: @data["frontCoverThumbnailUrl"]
      }.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    private

    def contributors
      Array(@data["contributors"]).map do |contributor|
        code = contributor.dig("role", "code")
        {
          name: contributor["name"] || [contributor["firstName"], contributor["lastName"]].compact.join(" "),
          role: Codes::CONTRIBUTOR_ROLES.fetch(code, code)
        }.compact
      end
    end

    def series
      collection = @data["collection"]
      return nil unless collection.is_a?(Hash) && collection["title"]

      { title: collection["title"], number: collection["number"] }.compact
    end

    def product_form
      form = @data["productForm"]
      return nil unless form.is_a?(Hash)

      { code: form["code"], label: form["shortLabel"] }.compact
    end

    def availability
      availability = @data["availability"]
      return nil unless availability.is_a?(Hash)

      Codes.availability(
        availability["code"],
        supply_date: date(availability["supplyDate"] || @data["supplyDate"])
      )
    end

    def price
      return { unpriced: "free" } if truthy?(@data["priceIsFreeOfCharge"] || @data["priceIsFreeofCharge"])
      return { unpriced: "unknown" } if truthy?(@data["priceIsToBeAnnounced"])

      prices = [
        dated_price(@data["priceRegulatedAction"], "14"),
        dated_price(@data["priceRegulated"], "04"),
        dated_price(@data["priceAction"], "12"),
        (@data.key?("price") ? { type_code: "02", amount: Prices.amount(@data["price"]) } : nil)
      ].compact.select { |p| p[:amount] }
      return nil if prices.empty?

      active = Prices.select_active(prices, today: @today)
      active && { amount: active[:amount], type: Codes::PRICE_TYPES[active[:type_code]] }
    end

    def dated_price(value, type_code)
      return nil unless value.is_a?(Hash)

      {
        type_code: type_code,
        amount: Prices.amount(value["price"]),
        start_date: date(value["startDate"]),
        end_date: date(value["endDate"])
      }
    end

    def date(value)
      return nil if value.nil? || value.to_s.empty?

      str = value.to_s
      str.match?(/\A\d{8}\z/) ? "#{str[0, 4]}-#{str[4, 2]}-#{str[6, 2]}" : str
    end

    def truthy?(value)
      value == true || value.to_s == "true"
    end

    def presence(value)
      value.nil? || value.to_s.strip.empty? ? nil : value
    end
  end
end
