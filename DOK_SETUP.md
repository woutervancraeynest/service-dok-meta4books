# Dok setup

## Register the service (admin)

1. Push this repository to a public HTTPS Git URL and tag a version, e.g. `v0.1.0`.
2. In Dok admin → Services, create a service:
   - Name: `meta4books` (tools become `meta4books.search_books`, …)
   - Git URL: the HTTPS repository URL
   - Version: the tag
   - Manifest: the contents of `manifest.json`
3. Move it through review → approved → published.

No OAuth configuration is needed.

## Project setup

1. Install and enable the Meta4books service in the project.
2. Enter the project's Boekenbank API key in the service settings (`api_key`, stored encrypted).
3. Smoke test from the agent: `meta4books.get_book` with a known ISBN, then `meta4books.search_books` with a query.

If `search_books` returns `UNAUTHORIZED` while `get_book` works, the key has no access to the search API; ask Meta4books (boekenbank@meta4books.be).
