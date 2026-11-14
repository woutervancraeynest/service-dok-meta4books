# Meta4books Dok Service

This repository contains a Dok Service that exposes the Boekenbank (Meta4books) search and ONIX products APIs through the Dok MCP proxy.

## Rules

- The service is stateless and read-only. Never download, cache or store covers, excerpts or product data.
- The API key travels in the query string. Never log request URLs, params containing the key, or raw responses; never include the key in error messages.
- Every tool returns bounded output: enforce the page limits (`search_books` 100, `list_products` 100 summaries / 25 full, `get_books` 100 ISBNs).
- Validate parameters before calling Boekenbank and return `INVALID_PARAMS` without a network call.
- Keep Boekenbank business rules from the official docs: price priority 14 → 04 → 12 → 02, imprint before publisher, list 51 codes 03 = replaces / 05 = replaced by.
- Keep the Boekenbank read timeout below Dok's 30 s proxy timeout.
- `manifest.json` and `DokService::TOOLS` must list the same tools (enforced by `spec/app_spec.rb`).

## Architecture

- `app.rb` — Sinatra endpoint that dispatches tool calls.
- `lib/meta4books/client.rb` — HTTP client and error mapping.
- `lib/meta4books/onix_product.rb` — ONIX 3.0 `<Product>` → normalized hash.
- `lib/meta4books/search_result.rb` — search API record → normalized hash.
- `lib/meta4books/prices.rb`, `codes.rb` — price priority and ONIX code lists.
- `lib/tools/` — tool handlers; `base.rb` holds parameter parsing and error handling.
- `spec/fixtures/` — ONIX and search fixtures (no real keys).

## Verification

```bash
bundle exec rspec
```
