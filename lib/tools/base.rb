require "date"
require_relative "../meta4books/client"

module Tools
  class InvalidParams < StandardError; end

  # Shared parameter handling for tool handlers. Handlers return plain hashes;
  # errors become {error:, code:} responses with HTTP 200 per the Dok contract.
  class Base
    def self.call(params:, context:)
      new(params, context).call
    rescue InvalidParams => e
      { error: e.message, code: "INVALID_PARAMS" }
    rescue Meta4books::Error => e
      { error: e.message, code: e.code }
    end

    def initialize(params, context)
      raise InvalidParams, "params must be an object" unless params.nil? || params.is_a?(Hash)

      @params = params || {}
      @context = context.is_a?(Hash) ? context : {}
    end

    private

    attr_reader :params

    def client
      @client ||= Meta4books::Client.from_context(@context)
    end

    def param(name)
      value = params[name.to_s]
      value.is_a?(String) ? value.strip.then { |v| v.empty? ? nil : v } : value
    end

    def list_param(name)
      value = param(name)
      list = value.is_a?(Array) ? value : value.to_s.split(",")
      list.map { |item| item.to_s.strip }.reject(&:empty?)
    end

    def integer_param(name, default:, min:, max:)
      value = param(name)
      return default if value.nil?

      number = value.is_a?(Float) && value == value.floor ? value.to_i : Integer(value.to_s, 10, exception: false)
      raise InvalidParams, "#{name} must be an integer" if number.nil?

      number.clamp(min, max)
    end

    def boolean_param(name)
      value = param(name)
      return nil if value.nil?
      return value if [true, false].include?(value)

      case value.to_s.downcase
      when "true", "1", "yes" then true
      when "false", "0", "no" then false
      else raise InvalidParams, "#{name} must be true or false"
      end
    end

    DATE_FORMAT = /\A(\d{4})-?(\d{2})-?(\d{2})\z/
    DATETIME_FORMAT = /\A(\d{4})-?(\d{2})-?(\d{2})[T ](\d{2}):?(\d{2})(?::?(\d{2}))?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?\z/

    # Accepts YYYY-MM-DD or YYYYMMDD, and with with_time also YYYY-MM-DDTHH:MM(:SS)
    # with an optional (ignored) timezone. Returns YYYYMMDD or YYYYMMDDHHMMSS.
    def date_param(name, with_time: false)
      value = param(name)
      return nil if value.nil?

      str = value.to_s
      if (match = str.match(DATE_FORMAT))
        return validated_date(name, match[1], match[2], match[3])
      end

      match = with_time && str.match(DATETIME_FORMAT)
      raise InvalidParams, "#{name} must be a date like 2026-11-14#{' or 2026-11-14T09:00' if with_time}" unless match

      hour, minute, second = match[4].to_i, match[5].to_i, match[6].to_i
      raise InvalidParams, "#{name} has an invalid time" if hour > 23 || minute > 59 || second > 59

      validated_date(name, match[1], match[2], match[3]) + format("%02d%02d%02d", hour, minute, second)
    end

    def validated_date(name, year, month, day)
      Date.new(year.to_i, month.to_i, day.to_i).strftime("%Y%m%d")
    rescue Date::Error
      raise InvalidParams, "#{name} is not a valid date"
    end

    def isbns_param(name, max:)
      isbns = list_param(name).map { |raw| normalize_isbn(raw) }.uniq
      raise InvalidParams, "#{name} must contain at least one ISBN" if isbns.empty?
      raise InvalidParams, "#{name} accepts at most #{max} ISBNs per call" if isbns.size > max

      isbns
    end

    def normalize_isbn(raw)
      cleaned = raw.to_s.upcase.gsub(/[^0-9X]/, "")
      return cleaned if cleaned.match?(/\A\d{13}\z/)
      return isbn10_to_13(cleaned) if cleaned.match?(/\A\d{9}[\dX]\z/)

      raise InvalidParams, "Invalid ISBN/EAN: #{raw.inspect} (expected 13 digits or an ISBN-10)"
    end

    def isbn10_to_13(isbn10)
      base = "978#{isbn10[0, 9]}"
      sum = base.chars.each_with_index.sum { |digit, index| digit.to_i * (index.even? ? 1 : 3) }
      "#{base}#{(10 - (sum % 10)) % 10}"
    end
  end
end
