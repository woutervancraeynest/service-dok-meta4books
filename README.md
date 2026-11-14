# service-dok-meta4books

Dok MCP service for the Boekenbank (Meta4books) book catalogue: free-text search, full ONIX product details normalized to JSON, filtered product lists and media links.

## Architecture

```text
Dok Agent -> Dok MCP proxy -> This service -> api.boekenbank.be
                                             ├── /api/zoek      (JSON search API)
                                             └── /api/products  (ONIX 3.0 products API)
```

The service is stateless. It stores nothing: covers and reading excerpts are returned as links to the public Boekenbank files.

## Tools

| Tool | API | Purpose |
|---|---|---|
| `search_books` | `/api/zoek` | Free-text search with filters; compact results |
| `get_book` | `/api/products` | All details of one ISBN |
| `get_books` | `/api/products` | All details of up to 100 ISBNs |
| `get_book_media` | `/api/products` | Front cover, back cover and excerpt links with last-modified date |
| `list_products` | `/api/products` | Structured filters (publisher ID, Thema, AVI, availability, …) and change tracking |

See `SERVICE_SPEC.md` for the output format and business rules.

## Configuration

Each Dok project sets its own Boekenbank key (`api_key`, a password field stored encrypted by Dok). It arrives on every call in `context.configuration.api_key`. The key is sent as a query parameter to Boekenbank, so request URLs are never logged and never included in error messages.

`BOEKENBANK_API_URL` (env, optional) overrides the base URL, e.g. for the Meta4books staging environment.

## Local development

```bash
bundle install
bundle exec rspec
bundle exec puma -C config/puma.rb
curl http://localhost:8080/health
curl -s -XPOST localhost:8080/call -H 'Content-Type: application/json' \
  -d '{"tool":"get_book","params":{"isbn":"9789045547145"},"context":{"configuration":{"api_key":"YOUR_KEY"}}}'
```

All HTTP calls are stubbed in the test suite (WebMock). Fixtures never contain a real key.

## Boekenbank documentation

- Products API: https://documentation.boekenbank.be (data users → "Using the Boekenbank ONIX product(s) API")
- Search API: https://documentation.boekenbank.be/s/c24mm6h6tf1uk7kpi2v0/data-users/d/c24mp716tf1uk7kpi480/using-the-boekenbank-search-api
- ONIX specification for data users: same space, "ONIX 3 XML specification Boekenbank for data users"
