require "date"

module Meta4books
  # Applies the Boekenbank pricing priority: an active special sale fixed
  # retail price (14), then an active fixed retail price (04), then an active
  # special sale retail price (12), otherwise the recommended retail price (02).
  module Prices
    module_function

    # prices: array of hashes with :type_code, :amount, :start_date, :end_date (ISO strings or nil).
    def select_active(prices, today: Date.today)
      Codes::PRICE_TYPES.each_key do |type_code|
        match = prices.find { |price| price[:type_code] == type_code && active?(price, today) }
        return match if match
      end
      nil
    end

    def active?(price, today = Date.today)
      start_date = parse(price[:start_date])
      end_date = parse(price[:end_date])
      return false if start_date && today < start_date
      return false if end_date && today > end_date

      true
    end

    def parse(value)
      return nil if value.nil? || value.to_s.empty?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    # Accepts "8,14", "8.14", 8.14 or nil.
    def amount(value)
      return nil if value.nil?
      return value.to_f if value.is_a?(Numeric)

      str = value.to_s.strip.tr(",", ".")
      str.empty? ? nil : Float(str, exception: false)
    end
  end
end
