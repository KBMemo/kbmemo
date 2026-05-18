# frozen_string_literal: true

# アップロード SVG の XSS 対策（script / イベント / ネストした object 等を除去）。
class MemoSvgSanitizer
  FORBIDDEN_ELEMENTS = %w[script style foreignObject iframe object embed].freeze

  def self.sanitize!(input)
    new.sanitize!(input)
  end

  def sanitize!(input)
    doc = Nokogiri::XML(input.to_s.b) { |cfg| cfg.strict.nonet.noblanks }
    root = doc.root
    raise MemoAssets::InvalidFile, "SVG のルート要素が不正です" unless root&.name == "svg"

    doc.xpath("//*").each do |node|
      if FORBIDDEN_ELEMENTS.include?(node.name)
        node.remove
        next
      end

      scrub_attributes(node)
    end

    doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
  rescue Nokogiri::XML::SyntaxError
    raise MemoAssets::InvalidFile, "SVG の形式が不正です"
  end

  private

  def scrub_attributes(node)
    node.attribute_nodes.each do |attr|
      name = attr.name
      value = attr.value.to_s.strip
      if name.match?(/\A(on|xmlns:)?on[a-z]+\z/i)
        node.remove_attribute(name)
      elsif %w[href xlink:href].include?(name) && value.match?(/\A(javascript|data):/i)
        node.remove_attribute(name)
      end
    end
  end
end
