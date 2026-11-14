require "net/http"
require "openssl"
require "uri"
require "json"
require "nokogiri"

module Meta4books
  class Error < StandardError
    attr_reader :code

    def initialize(message, code: "API_ERROR")
      super(message)
      @code = code
    end
  end

  # HTTP client for the Boekenbank ONIX products API and JSON search API.
  # The API key travels as a query parameter, so URLs are never logged or
  # included in error messages.
  class Client
    DEFAULT_BASE_URL = "https://api.boekenbank.be".freeze
    PRODUCTS_PATH = "/api/products".freeze
    SEARCH_PATH = "/api/zoek".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20

    ProductsResult = Struct.new(:products, :raw_count, :total, keyword_init: true)

    def self.from_context(context)
      api_key = context.dig("configuration", "api_key").to_s.strip
      if api_key.empty?
        raise Error.new(
          "No Boekenbank API key configured. Add it in the Meta4books service settings of this project.",
          code: "NOT_CONFIGURED"
        )
      end

      new(api_key: api_key)
    end

    def initialize(api_key:, base_url: ENV.fetch("BOEKENBANK_API_URL", DEFAULT_BASE_URL))
      @api_key = api_key
      @base_url = base_url
    end

    # Returns ProductsResult with Nokogiri <Product> nodes (namespaces removed).
    def products(params)
      response = get(PRODUCTS_PATH, params, accept: "application/xml, text/xml")
      doc = Nokogiri::XML(response.body)
      doc.remove_namespaces!
      unless doc.root&.name == "ONIXMessage"
        raise Error.new("Boekenbank products API returned an unexpected (non-ONIX) response.", code: "INVALID_RESPONSE")
      end

      nodes = doc.xpath("/ONIXMessage/Product")
      ProductsResult.new(
        products: nodes.reject { |p| p.at_xpath("ProductIdentifier").nil? },
        raw_count: nodes.size,
        total: integer_header(response, "x-tot-nr-of-products") || nodes.size
      )
    end

    def search(params)
      response = get(SEARCH_PATH, params, accept: "application/json")
      data = JSON.parse(response.body)
      return data if data.is_a?(Hash) && (data["data"].nil? || data["data"].is_a?(Array))

      raise Error.new("Boekenbank search API returned an unexpected response.", code: "INVALID_RESPONSE")
    rescue JSON::ParserError
      raise Error.new("Boekenbank search API returned an invalid JSON response.", code: "INVALID_RESPONSE")
    end

    private

    def get(path, params, accept:)
      uri = URI("#{@base_url.chomp('/')}#{path}")
      uri.query = URI.encode_www_form(params.merge(key: @api_key))

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri, "Accept" => accept))
      end

      check_status!(response)
      response
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error
      raise Error.new("Boekenbank did not respond in time. Try again with fewer ISBNs or a smaller limit.", code: "TIMEOUT")
    rescue SocketError, SystemCallError, IOError, Net::HTTPBadResponse, OpenSSL::SSL::SSLError => e
      raise Error.new("Could not reach Boekenbank (#{e.class}).", code: "UNREACHABLE")
    end

    def check_status!(response)
      status = response.code.to_i
      return if status == 200

      case status
      when 401, 403
        raise Error.new(
          "Boekenbank rejected the API key (HTTP #{status}). Check the key in the service settings; " \
          "the search API also requires a contract with Meta4books.",
          code: "UNAUTHORIZED"
        )
      when 429
        raise Error.new("Boekenbank rate limit reached (HTTP 429). Wait before retrying.", code: "RATE_LIMITED")
      else
        raise Error.new("Boekenbank returned HTTP #{status}.", code: "HTTP_#{status}")
      end
    end

    def integer_header(response, name)
      value = response[name]
      value && Integer(value, exception: false)
    end
  end
end
