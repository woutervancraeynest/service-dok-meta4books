# Meta4books service specification

Dok service contract: `GET /health` and `POST /call` as described in Dok's `docker/service-template/SERVICE_SPEC.md`. Tools appear in MCP as `{service-name}.{tool}`, e.g. `meta4books.search_books`.

Errors are returned with HTTP 200 as `{"error": "...", "code": "..."}`:

| Code | Meaning |
|---|---|
| `NOT_CONFIGURED` | No `api_key` in the project configuration |
| `INVALID_PARAMS` | Parameter validation failed (no API call was made) |
| `NOT_FOUND` | `get_book`: ISBN unknown in Boekenbank |
| `UNAUTHORIZED` | Boekenbank rejected the key (HTTP 401/403). The search API also needs a Meta4books contract or NDA |
| `RATE_LIMITED` | HTTP 429 |
| `TIMEOUT` / `UNREACHABLE` | Network problems (read timeout 20 s, below Dok's 30 s proxy timeout) |
| `HTTP_<status>` | Any other non-200 response |

## Tools

### `search_books`

Wraps `GET /api/zoek`. Requires `query` (at least 4 characters) or at least one filter. Default `limit` 20, maximum 100. Prices are requested by default (`send_prices=true`). Response:

```json
{
  "results": [{ "isbn": "...", "title": "...", "contributors": [{ "name": "...", "role": "author" }],
                "display_publisher": "...", "availability": { "code": "21", "status": "available", ... },
                "price": { "amount": 22.5, "type": "fixed_retail_price" }, "front_cover_thumbnail_url": "..." }],
  "total": 134, "limit": 20, "offset": 0, "next_offset": 20
}
```

The search API only returns the first three contributors and a cover thumbnail.

### `get_book` / `get_books`

Wraps `GET /api/products?isbns=…`. ISBN-10 input is converted to ISBN-13; hyphens are ignored. `get_books` accepts up to 100 ISBNs and returns `books`, `found` and `not_found`. An unknown ISBN yields an empty ONIX message (HTTP 200), never an error from Boekenbank.

Main fields of a book (empty values are omitted):

- `isbn`, `legal_deposit_number`, `title`, `subtitle`, `part_title`, `section_title`, `original_title`, `series {title, number}`
- `contributors [{sequence, role, role_code, name, first_name, prefix, last_name, organisation}]`. All-caps names are humanized.
- `product_form {code, label, detail, file_format, drm, description}`, `edition`, `languages [{code, role: text|original}]`, `pages`, `duration` (HH:MM:SS), `illustrations_note`
- `subjects {nur, thema [{code, main}], thema_qualifiers [{code, type}]}`, `audience {avi_old, avi_new, age_range {min, max, unit}}`, `measures {height_mm, width_mm, thickness_mm, weight_g}`
- `texts {description, description_html, promotional_text, annotation, feature}`. Text is converted from HTML; `description_html` keeps the original.
- `front_cover_url` (largest version), `front_cover_thumbnail_url`, `back_cover_url`, `excerpt_url`, `media [...]`
- `publisher {name, boekenbank_id, centraal_boekhuis_id, website}`, `imprint`, `display_publisher` (imprint when present, as Boekenbank recommends)
- `publishing_status`, `publication_date`, `first_publication_date`, `restrictions {information_restricted, sales_restricted}`
- `related {nstc, replaces [isbn], replaced_by [isbn]}` (ONIX list 51: 03 = replaces, 05 = replaced by)
- `supplier {name, distributor_code, fund_code, website}`, `orderable_on_boekenbank`
- `availability {code, label, label_nl, status, orderable, supply_date}` where `status` is `available`, `not_yet_available`, `temporarily_unavailable`, `unavailable` or `unknown`
- `price {active, all}` or `price {unpriced: free|unknown}`

#### Price priority

Each price in `price.all` has `type`, `amount` (incl. VAT), `discount_code`, `taxes`, optional `start_date`/`end_date` and `active`. `price.active` follows the Boekenbank rule:

1. active special sale fixed retail price (PriceType 14)
2. active fixed retail price, the Flemish GBP (04)
3. active special sale retail price (12)
4. recommended retail price (02)

A price is active when today falls between its start and end date (inclusive).

### `get_book_media`

Same request as `get_books`, but returns only `items [{isbn, media [{type, url, format, width, height, thumbnail, updated_at}]}]` and `not_found`. Types: `front_cover`, `back_cover`, `excerpt`.

**Storage policy:** the service never downloads or stores files. Agents link to the public Boekenbank URLs. When a file is needed as a deliverable, the agent downloads it to `/workspace/tmp/` and immediately calls Dok's `save_output` tool with `source_path`, which moves it to Active Storage and deletes it from the container. `updated_at` (ONIX ContentDate) tells whether a stored copy is outdated.

### `list_products`

Wraps `GET /api/products` with filters. Boekenbank requires `mutatiedatum` or `isbns` on every query. When the agent gives no `modified_since`, the service sends `mutatiedatum=20000101` and marks the response with `modified_since_defaulted: true`. At least one filter or date is required.

| Tool parameter | Boekenbank parameter |
|---|---|
| `modified_since` / `modified_until` / `created_since` | `mutatiedatum` / `lastmodifieduntil` / `creatiedatum` |
| `publication_date_from` / `_to` | `publicatiedatumvan` / `publicatiedatumtotenmet` |
| `publisher`, `publisher_ids`, `imprint`, `series` | `uitgever`, `publisherids`, `imprint`, `series` |
| `nurs`, `thema`, `avi_old`, `avi_new`, `languages` | `nurs`, `thema`, `aviold`, `avinew`, `taalcode` |
| `product_groups` (printbooks, ebooks, audiobooks, other) | `productvormen` (papierenboeken, ebooks, luisterboeken, overigeboeken) |
| `product_forms`, `availability`, `orderable`, `sales_restricted` | `productforms`, `availability`, `bestelbaar`, `salesrestriction` |
| `front_cover` (any, large), `has_description`, `has_excerpt` | `productimagefront` (1, 2), `productdescription`, `productexcerpt` |
| `distributor`, `fund_codes`, `discount_codes` | `distributor`, `fundcode`, `asw` |

`detail: "summary"` (default) returns up to 100 compact products per page; `detail: "full"` returns up to 25 full products. Paging uses `limit`, `offset`, `total` (header `X-Tot-Nr-Of-Products`) and `next_offset`.

Meta4books asks data users not to run heavy full loads without consulting them; the page limits enforce this.
