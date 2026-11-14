module Meta4books
  # Subsets of ONIX code lists that Boekenbank uses natively.
  module Codes
    # List 65 — label, Dutch label, orderable on Boekenbank, status group.
    AVAILABILITY = {
      "01" => ["Cancelled", "Zal niet verschijnen", false, "unavailable"],
      "10" => ["Not yet available", "Nog niet verschenen", true, "not_yet_available"],
      "12" => ["Not yet available, will be POD", "Nog niet verschenen, zal POD zijn", true, "not_yet_available"],
      "20" => ["Available", "Verschenen", true, "available"],
      "21" => ["In stock", "Verschenen, in voorraad", true, "available"],
      "22" => ["To order", "Verschenen, doorbestelling", true, "available"],
      "23" => ["Manufactured on demand", "Verschenen, printing-on-demand", true, "available"],
      "31" => ["Out of stock", "Verschenen, niet voorradig", true, "temporarily_unavailable"],
      "32" => ["Reprinting", "In herdruk", true, "temporarily_unavailable"],
      "44" => ["Apply direct", "Niet bestelbaar door de boekhandel", false, "unavailable"],
      "47" => ["Remaindered", "Verramsjt", false, "unavailable"],
      "51" => ["Out of print", "Uitverkocht", false, "unavailable"],
      "99" => ["Uncertain, contact supplier", "Onzeker, contacteer uitgever", false, "unavailable"],
      # Not native to Boekenbank, but valid in list 65.
      "40" => ["Not available (reason unspecified)", nil, false, "unavailable"],
      "41" => ["Not available, replaced by new product", nil, false, "unavailable"],
      "43" => ["No longer supplied by us", nil, false, "unavailable"],
      "45" => ["Not available, publisher indicates OP", nil, false, "unavailable"],
      "46" => ["Not available, withdrawn from sale", nil, false, "unavailable"],
      "48" => ["Not available, reissued", nil, false, "unavailable"],
      "49" => ["Not available, recalled", nil, false, "unavailable"],
      "50" => ["Not available, not sold separately", nil, false, "unavailable"],
      "52" => ["Not available, no longer stocked", nil, false, "unavailable"]
    }.freeze

    # List 64
    PUBLISHING_STATUS = {
      "01" => "Cancelled", "02" => "Forthcoming", "04" => "Active",
      "08" => "Inactive", "09" => "Unknown", "10" => "Remaindered"
    }.freeze

    # List 58, in Boekenbank priority order (highest first).
    PRICE_TYPES = {
      "14" => "special_sale_fixed_retail_price",
      "04" => "fixed_retail_price",
      "12" => "special_sale_retail_price",
      "02" => "recommended_retail_price"
    }.freeze

    # List 17
    CONTRIBUTOR_ROLES = {
      "A01" => "author", "A12" => "illustrator", "A13" => "photographer",
      "B01" => "editor", "B06" => "translator", "E07" => "narrator", "E08" => "musician"
    }.freeze

    # List 150 (Boekenbank subset)
    PRODUCT_FORMS = {
      "00" => "Undefined", "AA" => "Audio", "AB" => "Audio cassette", "AC" => "Audio CD",
      "AI" => "Audio DVD", "AJ" => "Downloadable audio file", "BA" => "Book",
      "BB" => "Hardback", "BC" => "Paperback", "BD" => "Loose-leaf", "BE" => "Spiral bound",
      "BH" => "Board book", "BI" => "Rag book", "BJ" => "Bath book", "BK" => "Novelty book",
      "BM" => "Big book", "BO" => "Fold-out book or chart", "CA" => "Sheet map",
      "DB" => "CD-ROM", "DF" => "Diskette", "DI" => "DVD-ROM", "DM" => "USB flash drive",
      "EA" => "Digital", "ED" => "Digital download", "PA" => "Miscellaneous print",
      "PB" => "Address book or diary", "PC" => "Calendar", "PD" => "Cards", "PH" => "Kit",
      "PI" => "Sheet music", "PJ" => "Postcard book or pack", "PK" => "Poster",
      "PM" => "Wallet or folder", "PO" => "Wallchart", "PP" => "Stickers",
      "PR" => "Notebook or blank book", "SA" => "Multiple-component retail product",
      "VA" => "Video", "VI" => "DVD video", "VJ" => "VHS video", "VO" => "Blu-ray",
      "XA" => "Trade-only material", "XB" => "Dumpbin, empty", "XC" => "Dumpbin, filled",
      "XD" => "Counterpack, empty", "XE" => "Counterpack, filled", "XL" => "Shrink-wrapped pack",
      "XM" => "Boxed pack", "ZA" => "General merchandise", "ZB" => "Doll or soft toy",
      "ZE" => "Game, puzzle or other toy"
    }.freeze

    # ProductFormDetail (list 175) used by Boekenbank for e-books.
    PRODUCT_FORM_DETAILS = { "E101" => "EPUB", "E107" => "PDF", "E116" => "Kindle" }.freeze

    # List 158
    RESOURCE_TYPES = { "01" => "front_cover", "02" => "back_cover", "15" => "excerpt" }.freeze

    # List 153
    TEXT_TYPES = { "05" => "description", "10" => "promotional_text", "02" => "annotation", "11" => "feature" }.freeze

    # List 27 — Thema qualifier schemes.
    THEMA_QUALIFIER_SCHEMES = {
      "94" => "place", "95" => "language", "96" => "time_period",
      "97" => "educational_purpose", "98" => "interest_age", "99" => "style"
    }.freeze

    # List 100 / Boekenbank AWSO discount codes.
    DISCOUNT_CODES = { "A" => "general", "W" => "scientific", "S" => "education", "O" => "other" }.freeze

    def self.availability(code, supply_date: nil)
      return nil if code.nil?

      label, label_nl, orderable, status = AVAILABILITY.fetch(code, [nil, nil, nil, "unknown"])
      {
        code: code,
        label: label,
        label_nl: label_nl,
        status: status,
        orderable: orderable,
        supply_date: supply_date
      }.compact
    end
  end
end
