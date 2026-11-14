require "spec_helper"

RSpec.describe DokService do
  describe "GET /health" do
    it "returns 200 OK" do
      get "/health"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("OK")
    end
  end

  describe "POST /call" do
    it "returns an error for an unknown tool" do
      call_tool("unknown_tool")

      expect(json_response["error"]).to include("Unknown tool")
    end

    it "returns 400 for invalid JSON" do
      post "/call", "not json", { "CONTENT_TYPE" => "application/json" }

      expect(last_response.status).to eq(400)
    end

    it "requires an API key" do
      call_tool("get_book", params: { "isbn" => "9789045547145" }, context: { "configuration" => {} })

      expect(json_response["code"]).to eq("NOT_CONFIGURED")
    end

    it "lists every manifest tool and nothing else" do
      manifest_tools = JSON.parse(File.read(File.join(__dir__, "..", "manifest.json")))["tools"].map { |t| t["name"] }

      expect(described_class::TOOLS.keys).to match_array(manifest_tools)
    end
  end

  describe "get_book" do
    it "returns the full book" do
      stub_products({ "isbns" => "9789045547145" }, body: fixture("onix_9789045547145.xml"))

      call_tool("get_book", params: { "isbn" => "978-90-455-4714-5" })

      expect(json_response.dig("book", "isbn")).to eq("9789045547145")
      expect(json_response.dig("book", "availability", "code")).to eq("51")
    end

    it "converts an ISBN-10" do
      stub_products({ "isbns" => "9789045547145" }, body: fixture("onix_9789045547145.xml"))

      call_tool("get_book", params: { "isbn" => "904554714X" })

      expect(json_response.dig("book", "isbn")).to eq("9789045547145")
    end

    it "reports an unknown ISBN" do
      stub_products({ "isbns" => "9781447203056" }, body: fixture("onix_empty.xml"))

      call_tool("get_book", params: { "isbn" => "9781447203056" })

      expect(json_response["code"]).to eq("NOT_FOUND")
    end

    it "rejects an invalid ISBN without calling the API" do
      call_tool("get_book", params: { "isbn" => "abc" })

      expect(json_response["code"]).to eq("INVALID_PARAMS")
    end

    it "maps an authorization failure without leaking the key" do
      stub_products({ "isbns" => "9789045547145" }, body: "", status: 403)

      call_tool("get_book", params: { "isbn" => "9789045547145" })

      expect(json_response["code"]).to eq("UNAUTHORIZED")
      expect(last_response.body).not_to include(SpecHelpers::API_KEY)
    end

    it "maps a timeout" do
      stub_request(:get, %r{api\.boekenbank\.be/api/products}).to_timeout

      call_tool("get_book", params: { "isbn" => "9789045547145" })

      expect(json_response["code"]).to eq("TIMEOUT")
    end
  end

  describe "get_books" do
    it "returns found books and missing ISBNs" do
      stub_products({ "isbns" => "9789045547145,9781447203056" }, body: fixture("onix_9789045547145.xml"))

      call_tool("get_books", params: { "isbns" => ["9789045547145", "9781447203056"] })

      expect(json_response["found"]).to eq(1)
      expect(json_response["not_found"]).to eq(["9781447203056"])
    end

    it "limits the number of ISBNs" do
      isbns = Array.new(101) { |i| format("9789000%06d", i) }

      call_tool("get_books", params: { "isbns" => isbns })

      expect(json_response["error"]).to include("at most 100")
    end
  end

  describe "get_book_media" do
    it "returns media links with a storage hint" do
      stub_products({ "isbns" => "9789006910896" }, body: fixture("onix_full.xml"))

      call_tool("get_book_media", params: { "isbns" => ["9789006910896"] })

      media = json_response.dig("items", 0, "media")
      expect(media.map { |m| m["type"] }).to eq(%w[front_cover front_cover back_cover excerpt])
      expect(json_response["hint"]).to include("save_output")
    end
  end

  describe "search_books" do
    it "maps parameters and normalizes results" do
      stub = stub_search(
        { "search_terms" => "\"Jeroen Meus\"", "search_fields" => "authors", "product_form_groups" => "printbooks",
          "sort" => "publication_date,desc", "send_prices" => "true", "limit" => "2", "offset" => "0",
          "publication_date_from" => "20240101" },
        body: fixture("search.json")
      )

      call_tool("search_books", params: {
        "query" => "\"Jeroen Meus\"", "fields" => ["authors"], "product_groups" => ["printbooks"],
        "sort_by" => "publication_date", "limit" => 2, "publication_date_from" => "2024-01-01"
      })

      expect(stub).to have_been_requested
      expect(json_response["total"]).to eq(5)
      expect(json_response["next_offset"]).to eq(2)
      expect(json_response["results"].first["isbn"]).to eq("9789492499134")
    end

    it "requires a query of at least 4 characters" do
      call_tool("search_books", params: { "query" => "abc" })

      expect(json_response["code"]).to eq("INVALID_PARAMS")
    end

    it "requires a query or a filter" do
      call_tool("search_books", params: {})

      expect(json_response["error"]).to include("query or at least one filter")
    end

    it "rejects unknown fields" do
      call_tool("search_books", params: { "query" => "koken", "fields" => ["isbn"] })

      expect(json_response["error"]).to include("Unknown fields")
    end
  end

  describe "list_products" do
    it "maps filters and defaults mutatiedatum" do
      stub = stub_products(
        { "uitgever" => "lannoo", "avinew" => "E3,M4", "bestelbaar" => "true", "productvormen" => "papierenboeken",
          "mutatiedatum" => "20000101", "limit" => "25", "offset" => "0" },
        body: fixture("onix_full.xml"), total: 40
      )

      call_tool("list_products", params: {
        "publisher" => "lannoo", "avi_new" => ["E3", "M4"], "orderable" => true, "product_groups" => ["printbooks"]
      })

      expect(stub).to have_been_requested
      expect(json_response["products"].first.keys).to include("isbn", "title", "front_cover_url")
      expect(json_response["total"]).to eq(40)
      expect(json_response["next_offset"]).to eq(1)
      expect(json_response["modified_since_defaulted"]).to be(true)
    end

    it "supports change tracking with full detail" do
      stub_products({ "mutatiedatum" => "20261101090000", "limit" => "25" }, body: fixture("onix_full.xml"), total: 1)

      call_tool("list_products", params: { "modified_since" => "2026-11-01T09:00", "detail" => "full", "limit" => 50 })

      expect(json_response["limit"]).to eq(25)
      expect(json_response["products"].first).to have_key("contributors")
      expect(json_response["next_offset"]).to be_nil
    end

    it "requires a filter" do
      call_tool("list_products", params: { "limit" => 5 })

      expect(json_response["code"]).to eq("INVALID_PARAMS")
    end
  end
end
