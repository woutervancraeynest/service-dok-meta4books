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
      @params = params || {}
      @context = context || {}
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

      number = Integer(value.to_s, exception: false)
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

    # Accepts YYYY-MM-DD, YYYYMMDD, YYYY-MM-DDTHH:MM(:SS) or YYYYMMDDHHMMSS.
    def date_param(name, with_time: false)
      value = param(name)
      return nil if value.nil?

      digits = value.to_s.gsub(/[^0-9]/, "")
      valid = with_time ? [8, 12, 14].include?(digits.length) : digits.length == 8
      raise InvalidParams, "#{name} must be a date like 2026-11-14#{' or 2026-11-14T09:00' if with_time}" unless valid

      digits.length == 12 ? "#{digits}00" : digits
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
