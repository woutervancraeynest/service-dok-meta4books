require_relative "base"
require_relative "../meta4books/onix_product"

module Tools
  # Full product details for up to 100 ISBNs via the ONIX products API.
  class GetBooks < Base
    MAX_ISBNS = 100

    def call
      isbns = isbns_param("isbns", max: MAX_ISBNS)
      books = fetch(isbns)
      found = books.map { |book| book[:isbn] }

      {
        books: books,
        found: found.size,
        not_found: isbns - found
      }
    end

    private

    def fetch(isbns)
      result = client.products(isbns: isbns.join(","))
      result.products.map { |node| Meta4books::OnixProduct.new(node).to_h }
    end
  end

  class GetBook < GetBooks
    def call
      isbn = normalize_isbn(param("isbn") || raise(InvalidParams, "isbn is required"))
      book = fetch([isbn]).find { |b| b[:isbn] == isbn }
      return { error: "ISBN #{isbn} was not found in Boekenbank", code: "NOT_FOUND" } unless book

      { book: book }
    end
  end

  # Only the media links (covers and reading excerpt) with their last-modified date.
  class GetBookMedia < GetBooks
    def call
      isbns = isbns_param("isbns", max: MAX_ISBNS)
      result = client.products(isbns: isbns.join(","))
      items = result.products.map do |node|
        product = Meta4books::OnixProduct.new(node)
        { isbn: product.isbn, media: product.media }
      end
      found = items.map { |item| item[:isbn] }

      {
        items: items,
        not_found: isbns - found,
        hint: "To keep a file: download it to /workspace/tmp/ and immediately call the Dok save_output tool " \
              "with source_path. Use updated_at to decide whether a stored copy is outdated."
      }
    end
  end
end
