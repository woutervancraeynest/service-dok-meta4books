require "nokogiri"
require_relative "codes"
require_relative "prices"

module Meta4books
  # Maps one Boekenbank ONIX 3.0 <Product> node (namespaces removed) to a
  # normalized hash. See "ONIX 3 XML specification Boekenbank for data users".
  class OnixProduct
    def initialize(node, today: Date.today)
      @node = node
      @today = today
    end

    def isbn
      @isbn ||= text("ProductIdentifier[ProductIDType='03']/IDValue") ||
                text("ProductIdentifier[ProductIDType='15']/IDValue") ||
                text("ProductIdentifier/IDValue")
    end

    def to_h
      {
        isbn: isbn,
        legal_deposit_number: text("ProductIdentifier[ProductIDType='17']/IDValue"),
        **titles,
        series: series,
        contributors: contributors,
        product_form: product_form,
        edition: edition,
        languages: languages,
        pages: integer(text("DescriptiveDetail/Extent[ExtentType='00']/ExtentValue")),
        duration: duration,
        illustrations_note: text("DescriptiveDetail/IllustrationsNote"),
        subjects: subjects,
        audience: audience,
        measures: measures,
        texts: texts,
        **media_urls,
        media: media,
        publisher: publisher,
        imprint: imprint,
        display_publisher: imprint || publisher[:name],
        publishing_status: publishing_status,
        publication_date: publishing_date("01"),
        first_publication_date: publishing_date("11"),
        restrictions: restrictions,
        related: related,
        supplier: supplier,
        orderable_on_boekenbank: orderable_on_boekenbank,
        availability: availability,
        price: price
      }.then { |hash| compact_deep(hash) }
    end

    def summary
      full = to_h
      {
        isbn: full[:isbn],
        title: full[:title],
        subtitle: full[:subtitle],
        authors: Array(full[:contributors]).select { |c| c[:role] == "author" }.map { |c| c[:name] },
        display_publisher: full[:display_publisher],
        series: full[:series],
        product_form: full.dig(:product_form, :label),
        publication_date: full[:publication_date],
        availability: full[:availability]&.slice(:code, :label, :status, :supply_date),
        orderable_on_boekenbank: full[:orderable_on_boekenbank],
        price: full.dig(:price, :active)&.slice(:amount, :type),
        front_cover_url: full[:front_cover_url]
      }.then { |hash| compact_deep(hash) }
    end

    def media
      @media ||= @node.xpath("CollateralDetail/SupportingResource").flat_map do |resource|
        type = Codes::RESOURCE_TYPES.fetch(text("ResourceContentType", resource), "other")
        resource.xpath("ResourceVersion").filter_map do |version|
          url = text("ResourceLink", version)
          next unless url

          {
            type: type,
            url: url,
            format: media_format(text("ResourceVersionFeature[ResourceVersionFeatureType='01']/FeatureValue", version), url),
            height: integer(text("ResourceVersionFeature[ResourceVersionFeatureType='02']/FeatureValue", version)),
            width: integer(text("ResourceVersionFeature[ResourceVersionFeatureType='03']/FeatureValue", version)),
            thumbnail: url.include?("/thumbnail/"),
            updated_at: datetime(text("ContentDate/Date", version))
          }.compact
        end
      end
    end

    private

    attr_reader :node

    def titles
      detail = node.at_xpath("DescriptiveDetail/TitleDetail[TitleType='01']")
      elements = detail ? detail.xpath("TitleElement").to_a : []
      main = elements.find { |e| e.at_xpath("Subtitle") } ||
             elements.max_by { |e| integer(text("TitleElementLevel", e)) || 0 }
      others = (elements - [main]).sort_by { |e| -(integer(text("TitleElementLevel", e)) || 0) }

      {
        title: main && text("TitleText", main),
        subtitle: main && text("Subtitle", main),
        part_title: others[0] && text("TitleText", others[0]),
        section_title: others[1] && text("TitleText", others[1]),
        original_title: text("DescriptiveDetail/TitleDetail[TitleType='03']/TitleElement/TitleText")
      }
    end

    def series
      element = node.at_xpath("DescriptiveDetail/Collection/TitleDetail/TitleElement")
      return nil unless element

      { title: text("TitleText", element), number: text("PartNumber", element) }
    end

    def contributors
      node.xpath("DescriptiveDetail/Contributor").map do |contributor|
        role_code = text("ContributorRole", contributor)
        first_name = humanize_name(text("NamesBeforeKey", contributor))
        prefix = text("PrefixToKey", contributor)
        last_name = humanize_name(text("KeyNames", contributor))
        corporate = text("CorporateName", contributor)

        {
          sequence: integer(text("SequenceNumber", contributor)),
          role: Codes::CONTRIBUTOR_ROLES.fetch(role_code, role_code),
          role_code: role_code,
          name: corporate || [first_name, prefix, last_name].compact.join(" "),
          first_name: first_name,
          prefix: prefix,
          last_name: last_name,
          organisation: corporate ? true : nil
        }
      end.sort_by { |c| c[:sequence] || 0 }
    end

    def product_form
      code = text("DescriptiveDetail/ProductForm")
      return nil unless code

      detail = text("DescriptiveDetail/ProductFormDetail")
      {
        code: code,
        label: Codes::PRODUCT_FORMS.fetch(code, code),
        detail: detail,
        file_format: Codes::PRODUCT_FORM_DETAILS[detail],
        drm: text("DescriptiveDetail/EpubTechnicalProtection"),
        description: text("DescriptiveDetail/ProductFormDescription")
      }
    end

    def edition
      {
        type: text("DescriptiveDetail/EditionType"),
        number: integer(text("DescriptiveDetail/EditionNumber")),
        statement: text("DescriptiveDetail/EditionStatement")
      }
    end

    def languages
      node.xpath("DescriptiveDetail/Language").map do |language|
        {
          code: text("LanguageCode", language),
          role: text("LanguageRole", language) == "02" ? "original" : "text"
        }
      end
    end

    # ExtentValue is HHHMMSS for ExtentType 09.
    def duration
      raw = text("DescriptiveDetail/Extent[ExtentType='09']/ExtentValue")
      return nil unless raw&.match?(/\A\d+\z/)

      padded = raw.rjust(7, "0")
      hours = padded[0..-5].to_i
      minutes = padded[-4..-3].to_i
      seconds = padded[-2..].to_i
      format("%02d:%02d:%02d", hours, minutes, seconds)
    end

    def subjects
      subjects = node.xpath("DescriptiveDetail/Subject")
      nur = subjects.find { |s| text("SubjectSchemeIdentifier", s) == "32" }
      thema = subjects.select { |s| text("SubjectSchemeIdentifier", s) == "93" }
      qualifiers = subjects.select { |s| Codes::THEMA_QUALIFIER_SCHEMES.key?(text("SubjectSchemeIdentifier", s)) }

      {
        nur: nur && text("SubjectCode", nur),
        thema: thema.map { |s| { code: text("SubjectCode", s), main: s.at_xpath("MainSubject") ? true : nil } },
        thema_qualifiers: qualifiers.map do |s|
          { code: text("SubjectCode", s), type: Codes::THEMA_QUALIFIER_SCHEMES[text("SubjectSchemeIdentifier", s)] }
        end
      }
    end

    def audience
      audiences = node.xpath("DescriptiveDetail/Audience")
      avi = lambda do |type|
        audiences.select { |a| text("AudienceCodeType", a) == type }
                 .map { |a| text("AudienceCodeValue", a).to_s.sub(/\AAVI[\s-]*/i, "") }
      end

      { avi_old: avi.call("09"), avi_new: avi.call("18"), age_range: age_range }
    end

    def age_range
      ranges = node.xpath("DescriptiveDetail/AudienceRange")
      return nil if ranges.empty?

      result = {}
      ranges.each do |range|
        unit = text("AudienceRangeQualifier", range) == "16" ? "months" : "years"
        precisions = range.xpath("AudienceRangePrecision").map(&:text)
        values = range.xpath("AudienceRangeValue").map { |v| integer(v.text) }
        precisions.zip(values).each do |precision, value|
          case precision
          when "01" then result.merge!(min: value, max: value, unit: unit)
          when "03" then result.merge!(min: value, unit: unit)
          when "04" then result.merge!(max: value, unit: unit)
          end
        end
      end
      result
    end

    def measures
      measure = ->(type) { integer(text("DescriptiveDetail/Measure[MeasureType='#{type}']/Measurement")) }
      { height_mm: measure.call("01"), width_mm: measure.call("02"), thickness_mm: measure.call("03"), weight_g: measure.call("08") }
    end

    def texts
      node.xpath("CollateralDetail/TextContent").each_with_object({}) do |content, result|
        key = Codes::TEXT_TYPES[text("TextType", content)]
        text_node = content.at_xpath("Text")
        next unless text_node

        # XHTML (textformat 05) arrives as child elements, HTML (02) as escaped/CDATA text.
        raw = (text_node.element_children.any? ? text_node.inner_html : text_node.text).strip
        next if key.nil? || raw.empty? || result.key?(key.to_sym)

        result[key.to_sym] = html_to_text(raw)
        result[:description_html] = raw if key == "description" && raw.match?(/<[a-z][^>]*>/i)
      end
    end

    def media_urls
      by_type = media.group_by { |m| m[:type] }
      front = Array(by_type["front_cover"])
      {
        front_cover_url: best(front)&.dig(:url),
        front_cover_thumbnail_url: front.find { |m| m[:thumbnail] }&.dig(:url),
        back_cover_url: best(Array(by_type["back_cover"]))&.dig(:url),
        excerpt_url: Array(by_type["excerpt"]).first&.dig(:url)
      }
    end

    def best(versions)
      versions.max_by { |m| [m[:thumbnail] ? 0 : 1, (m[:width] || 0) * (m[:height] || 0)] }
    end

    def publisher
      publisher = node.at_xpath("PublishingDetail/Publisher[PublishingRole='01']") ||
                  node.at_xpath("PublishingDetail/Publisher")
      return {} unless publisher

      {
        name: text("PublisherName", publisher),
        boekenbank_id: text("PublisherIdentifier[PublisherIDType='01']/IDValue", publisher),
        centraal_boekhuis_id: text("PublisherIdentifier[PublisherIDType='10']/IDValue", publisher),
        website: text("Website/WebsiteLink", publisher)
      }
    end

    def imprint
      text("PublishingDetail/Imprint/ImprintName")
    end

    def publishing_status
      code = text("PublishingDetail/PublishingStatus")
      code && { code: code, label: Codes::PUBLISHING_STATUS[code] }
    end

    def publishing_date(role)
      date(text("PublishingDetail/PublishingDate[PublishingDateRole='#{role}']/Date"))
    end

    def restrictions
      types = node.xpath("PublishingDetail/SalesRights/SalesRestriction/SalesRestrictionType").map(&:text)
      { information_restricted: types.include?("03"), sales_restricted: types.include?("07") }
    end

    # List 51: 03 = this product replaces the related product, 05 = this product is replaced by it.
    def related
      related_isbns = lambda do |code|
        node.xpath("RelatedMaterial/RelatedProduct[ProductRelationCode='#{code}']/ProductIdentifier[ProductIDType='03']/IDValue")
            .map { |id| id.text.strip }.uniq
      end

      {
        nstc: text("RelatedMaterial/RelatedWork/WorkIdentifier[IDTypeName='NSTC']/IDValue"),
        replaces: related_isbns.call("03"),
        replaced_by: related_isbns.call("05")
      }
    end

    def supply_detail
      @supply_detail ||= node.at_xpath("ProductSupply/SupplyDetail")
    end

    def supplier
      supplier = supply_detail&.at_xpath("Supplier")
      return nil unless supplier

      {
        name: text("SupplierName", supplier),
        distributor_code: text("SupplierIdentifier[SupplierIDType='12']/IDValue", supplier),
        fund_code: text("SupplierIdentifier[SupplierIDType='13']/IDValue", supplier),
        website: text("Website/WebsiteLink", supplier)
      }
    end

    def orderable_on_boekenbank
      value = text("SupplierOwnCoding[SupplierCodeTypeName='Boekenbank']/SupplierCodeValue", supply_detail) if supply_detail
      return nil unless value

      value.casecmp?("yes")
    end

    def availability
      return nil unless supply_detail

      Codes.availability(
        text("ProductAvailability", supply_detail),
        supply_date: date(text("SupplyDate/Date", supply_detail))
      )
    end

    def price
      return nil unless supply_detail

      unpriced = text("UnpricedItemType", supply_detail)
      return { unpriced: unpriced == "01" ? "free" : "unknown" } if unpriced

      prices = supply_detail.xpath("Price").map { |price_node| price_hash(price_node) }
      return { unpriced: "unknown" } if prices.empty?

      { active: Prices.select_active(prices, today: @today), all: prices }
    end

    def price_hash(price_node)
      type_code = text("PriceType", price_node)
      discount = text("DiscountCoded/DiscountCode", price_node)
      price = {
        type: Codes::PRICE_TYPES.fetch(type_code, type_code),
        type_code: type_code,
        amount: Prices.amount(text("PriceAmount", price_node)),
        currency: text("CurrencyCode", price_node),
        discount_code: discount,
        discount_group: Codes::DISCOUNT_CODES[discount],
        taxes: price_node.xpath("Tax").map do |tax|
          {
            rate_code: text("TaxRateCode", tax),
            rate_percent: Prices.amount(text("TaxRatePercent", tax)),
            taxable_amount: Prices.amount(text("TaxableAmount", tax))
          }.compact
        end,
        start_date: date(text("PriceDate[PriceDateRole='14']/Date", price_node)),
        end_date: date(text("PriceDate[PriceDateRole='15']/Date", price_node))
      }
      price.merge(active: Prices.active?(price, @today)).compact
    end

    def text(xpath, context = node)
      value = context.at_xpath(xpath)&.text&.strip
      value.nil? || value.empty? ? nil : value
    end

    def integer(value)
      value && Integer(value.to_s, 10, exception: false)
    end

    # YYYYMMDD -> YYYY-MM-DD
    def date(value)
      return nil unless value

      match = value.match(/\A(\d{4})(\d{2})(\d{2})/)
      match ? "#{match[1]}-#{match[2]}-#{match[3]}" : value
    end

    # YYYYMMDDThhmm(+zzzz) -> ISO 8601
    def datetime(value)
      return nil unless value

      match = value.match(/\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})([+-]\d{2})?(\d{2})?/)
      return date(value) unless match

      zone = match[6] ? "#{match[6]}:#{match[7] || '00'}" : ""
      "#{match[1]}-#{match[2]}-#{match[3]}T#{match[4]}:#{match[5]}:00#{zone}"
    end

    def media_format(feature, url)
      case feature
      when "D502" then "jpg"
      when "D401" then "pdf"
      else File.extname(url.to_s).delete(".").downcase.then { |ext| ext.empty? ? nil : ext }
      end
    end

    def humanize_name(name)
      return nil if name.nil?
      return name unless name == name.upcase && name.match?(/[A-Z]/)

      name.downcase.gsub(/(\A|[\s\-.])(\p{L})/) { "#{$1}#{$2.upcase}" }
    end

    def html_to_text(html)
      fragment = Nokogiri::HTML::DocumentFragment.parse(html)
      fragment.css("br").each { |br| br.replace("\n") }
      fragment.css("p, li, div").each { |block| block.add_next_sibling("\n") }
      fragment.text.gsub(/[ \t]+/, " ").gsub(/ *\n */, "\n").gsub(/\n{3,}/, "\n\n").strip
    end

    def compact_deep(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), result|
          compacted = compact_deep(val)
          result[key] = compacted unless compacted.nil? || (compacted.respond_to?(:empty?) && compacted.empty?)
        end
      when Array
        value.map { |item| compact_deep(item) }.reject { |item| item.nil? || (item.respond_to?(:empty?) && item.empty?) }
      else
        value
      end
    end
  end
end
