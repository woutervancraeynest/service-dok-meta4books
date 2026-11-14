require "spec_helper"

RSpec.describe Meta4books::SearchResult do
  let(:records) { JSON.parse(fixture("search.json"))["data"] }

  it "normalizes a search record" do
    result = described_class.new(records.first, today: Date.new(2026, 11, 14)).to_h

    expect(result).to include(
      isbn: "9789492499134",
      title: "Discover the Japanse art of life",
      display_publisher: "Zen Books",
      contributors: [{ name: "Pierre Du Marché", role: "author" }],
      product_form: { code: "BB", label: "Hardback" },
      languages: ["eng"],
      thema: ["VXM"],
      publication_date: "2021-04-29",
      series: { title: "The Art of Living", number: "Part II" }
    )
    expect(result[:availability]).to include(code: "10", status: "not_yet_available", supply_date: "2021-07-16")
  end

  it "applies the price priority with comma decimals" do
    active = described_class.new(records.first, today: Date.new(2026, 11, 14)).to_h[:price]
    expired = described_class.new(records.first, today: Date.new(2026, 12, 14)).to_h[:price]

    expect(active).to eq(amount: 7.0, type: "special_sale_retail_price")
    expect(expired).to eq(amount: 10.0, type: "recommended_retail_price")
  end

  it "handles free products and blank imprints" do
    result = described_class.new(records.last).to_h

    expect(result[:price]).to eq(unpriced: "free")
    expect(result[:display_publisher]).to eq("Uitgeverij X")
    expect(result).not_to have_key(:imprint)
  end
end
