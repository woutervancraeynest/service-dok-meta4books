require "spec_helper"

RSpec.describe Meta4books::OnixProduct do
  def product_from(fixture_name, today: Date.new(2026, 11, 14))
    doc = Nokogiri::XML(fixture(fixture_name))
    doc.remove_namespaces!
    described_class.new(doc.at_xpath("/ONIXMessage/Product"), today: today)
  end

  describe "#to_h with a complete record" do
    subject(:book) { product_from("onix_full.xml").to_h }

    it "maps identifiers and titles" do
      expect(book).to include(
        isbn: "9789006910896",
        legal_deposit_number: "D/2020/45/416",
        title: "Look & you will find",
        subtitle: "This is the subtitle",
        part_title: "This is the part title",
        section_title: "This is the section title",
        original_title: "The original title",
        series: { title: "De X-reeks", number: "15" }
      )
    end

    it "orders contributors and humanizes all-caps names" do
      expect(book[:contributors].map { |c| c[:name] }).to eq(
        ["Judith A. Cohen", "Karin de Galan", "Berlin Philharmonic Orchestra"]
      )
      expect(book[:contributors].last).to include(role: "musician", organisation: true)
    end

    it "maps descriptive details" do
      expect(book[:product_form]).to include(code: "BB", label: "Hardback")
      expect(book[:edition]).to eq(type: "REV", number: 2, statement: "Herziene druk")
      expect(book[:languages]).to eq([{ code: "dut", role: "text" }, { code: "eng", role: "original" }])
      expect(book[:pages]).to eq(200)
      expect(book[:duration]).to eq("02:05:00")
      expect(book[:measures]).to eq(height_mm: 240, width_mm: 170, thickness_mm: 22, weight_g: 540)
      expect(book[:illustrations_note]).to eq("With 15 full-colour photographs.")
    end

    it "maps subjects and audience" do
      expect(book[:subjects]).to eq(
        nur: "184",
        thema: [{ code: "AFC", main: true }, { code: "GLF" }],
        thema_qualifiers: [{ code: "3B-AA-E", type: "time_period" }]
      )
      expect(book[:audience]).to eq(avi_old: ["4"], avi_new: ["E3"], age_range: { min: 6, max: 9, unit: "years" })
    end

    it "converts description HTML to text and keeps the HTML" do
      expect(book[:texts][:description]).to eq("Empower success\nSet your priorities\nSecond paragraph & more.")
      expect(book[:texts][:description_html]).to include("<p>")
      expect(book[:texts][:promotional_text]).to eq("The road to high performance")
    end

    it "picks the largest front cover and exposes all media" do
      expect(book[:front_cover_url]).to end_with("/large/9789/006/910/9789006910896.jpg")
      expect(book[:front_cover_thumbnail_url]).to include("/thumbnail/")
      expect(book[:back_cover_url]).to end_with("/back/9789006910896.jpg")
      expect(book[:excerpt_url]).to end_with(".pdf")
      expect(book[:media].first).to include(type: "front_cover", format: "jpg", width: 200, height: 283,
                                            updated_at: "2021-03-31T16:46:00+02:00")
    end

    it "maps publishing, restrictions and related products" do
      expect(book[:publisher]).to include(name: "Ambo/Anthos Uitgevers", boekenbank_id: "45415447",
                                          centraal_boekhuis_id: "7600427")
      expect(book[:display_publisher]).to eq("Manteau")
      expect(book[:publishing_status]).to eq(code: "04", label: "Active")
      expect(book[:publication_date]).to eq("2019-06-15")
      expect(book[:first_publication_date]).to eq("1982-11-04")
      expect(book[:restrictions]).to eq(information_restricted: false, sales_restricted: true)
      expect(book[:related]).to eq(nstc: "545214552", replaces: ["9789464311143"], replaced_by: ["5410574910394"])
    end

    it "maps supply, availability and orderability" do
      expect(book[:supplier]).to include(distributor_code: "LAN", fund_code: "LANUHS", name: "Distrimedia (Lannoo)")
      expect(book[:orderable_on_boekenbank]).to be(true)
      expect(book[:availability]).to include(code: "32", label: "Reprinting", status: "temporarily_unavailable",
                                             orderable: true, supply_date: "2027-04-09")
    end

    it "selects the active price using the Boekenbank priority" do
      expect(book[:price][:active]).to include(type: "fixed_retail_price", amount: 22.5)
      expect(book[:price][:all].map { |p| [p[:type_code], p[:active]] }).to eq([["02", true], ["04", true], ["14", false]])
    end

    it "prefers an active special sale fixed price" do
      book = product_from("onix_full.xml", today: Date.new(2026, 11, 5)).to_h

      expect(book[:price][:active]).to include(type: "special_sale_fixed_retail_price", amount: 19.99)
    end

    it "falls back to the recommended retail price" do
      book = product_from("onix_full.xml", today: Date.new(2027, 6, 1)).to_h

      expect(book[:price][:active]).to include(type: "recommended_retail_price", amount: 24.99)
    end
  end

  describe "a real Boekenbank response" do
    subject(:book) { product_from("onix_9789045547145.xml").to_h }

    it "maps the core fields" do
      expect(book).to include(isbn: "9789045547145", title: "7 à dire 1 - handleiding (+ dvd en luister-cd)",
                              display_publisher: "De Boeck Uitgeverij", orderable_on_boekenbank: false)
      expect(book[:contributors].map { |c| c[:name] }).to eq(["Hugo Scheyving", "Tanka T'sjoen"])
      expect(book[:availability]).to include(code: "51", status: "unavailable")
      expect(book[:price][:active]).to include(amount: 97.0, discount_group: "education")
      expect(book[:price][:active][:taxes].size).to eq(2)
      expect(book[:front_cover_url]).to include("9789045547145.jpg")
    end
  end

  describe "#summary" do
    it "returns a compact representation" do
      summary = product_from("onix_full.xml").summary

      expect(summary.keys).to include(:isbn, :title, :authors, :availability, :price, :front_cover_url)
      expect(summary[:authors]).to eq(["Judith A. Cohen", "Karin de Galan"])
      expect(summary[:price]).to eq(amount: 22.5, type: "fixed_retail_price")
    end
  end
end
