# frozen_string_literal: true

# アップロード SVG の XSS 対策（script / イベント / ネストした object 等を除去）。
# Mermaid（Kroki）SVG は <style> の fill/stroke と foreignObject 内 HTML ラベルに依存する。
class MemoSvgSanitizer
  FORBIDDEN_ELEMENTS = %w[script iframe object embed].freeze

  FOREIGN_OBJECT_FORBIDDEN = %w[
    script iframe object embed form input textarea button link meta style img svg
  ].freeze

  FOREIGN_OBJECT_ALLOWED = %w[motion div span p br b i strong em].freeze

  UNSAFE_CSS_PATTERN = /
    @import
    | javascript:
    | expression\s*\(
    | -moz-binding
    | behavior\s*:
    | url\s*\(\s*['"]?\s*javascript:
  /ix

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

      if node.name == "style"
        sanitize_style_element!(node)
        next
      end

      if node.name == "foreignObject"
        sanitize_foreign_object!(node)
      end

      scrub_attributes(node)
    end

    doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
  rescue Nokogiri::XML::SyntaxError
    raise MemoAssets::InvalidFile, "SVG の形式が不正です"
  end

  private

  def sanitize_style_element!(node)
    css = node.text.to_s
    css = css.gsub(UNSAFE_CSS_PATTERN, "/* blocked */") if css.match?(UNSAFE_CSS_PATTERN)
    node.children.remove
    node.add_child(Nokogiri::XML::Text.new(css, node.document))
  end

  def sanitize_foreign_object!(node)
    node.xpath(".//*").each do |child|
      next if child.text? || child.cdata?

      if FOREIGN_OBJECT_FORBIDDEN.include?(child.name)
        child.remove
      elsif !FOREIGN_OBJECT_ALLOWED.include?(child.name)
        child.replace(Nokogiri::XML::Text.new(child.text.to_s, node.document))
      else
        scrub_attributes(child)
      end
    end
  end

  def scrub_attributes(node)
    node.attribute_nodes.each do |attr|
      name = attr.name
      value = attr.value.to_s.strip
      if name.match?(/\A(on|xmlns:)?on[a-z]+\z/i)
        node.remove_attribute(name)
      elsif %w[href xlink:href].include?(name) && value.match?(/\A(javascript|data):/i)
        node.remove_attribute(name)
      elsif name == "style" && value.match?(UNSAFE_CSS_PATTERN)
        node.remove_attribute(name)
      end
    end
  end
end
