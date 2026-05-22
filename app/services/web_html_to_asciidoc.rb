# frozen_string_literal: true

require "nokogiri"

# Convert clipboard HTML (web page fragment) to AsciiDoc.
# Port of app/javascript/adoc_editor/asciidoc/webHtmlToAsciidoc.js
class WebHtmlToAsciidoc
  BLOCK_CONTAINER_TAGS = %w[
    address article aside blockquote details div dl fieldset figure footer form header main nav ol p pre section table ul
  ].to_set.freeze

  SKIP_TAGS = %w[script style noscript meta link head svg iframe].to_set.freeze

  class << self
    def convert(html)
      trimmed = WebPasteMetadata.strip_kbmemo_comment(html.to_s.strip)
      return "" if trimmed.blank?

      doc = Nokogiri::HTML.fragment(trimmed)
      sanitize_tree(doc)
      blocks = doc.children.filter_map { |child| convert_top_level_node(child) }
      normalize_blocks(blocks)
    end

    private

    def sanitize_tree(root)
      root.css("*").each do |el|
        tag = el.name.downcase
        if SKIP_TAGS.include?(tag)
          el.remove
          next
        end

        el.attribute_nodes.each do |attr|
          el.remove_attribute(attr.name) if attr.name.match?(/\Aon/i)
        end
      end
    end

    def normalize_blocks(blocks)
      blocks
        .map { |block| block.gsub(/\n{3,}/, "\n\n").strip }
        .reject(&:blank?)
        .join("\n\n")
    end

    def convert_top_level_node(node)
      case node
      when Nokogiri::XML::Text
        text = normalize_whitespace(node.text)
        text.presence
      when Nokogiri::XML::Element
        convert_element_node(node)
      end
    end

    def convert_element_node(el)
      tag = el.name.downcase
      return nil if tag == "br"

      if tag.match?(/\Ah[1-6]\z/)
        level = tag[1].to_i
        marker = level == 1 ? "=" : "=" * level
        text = inline_text(el)
        return "#{marker} #{text}" if text.present?
      end

      case tag
      when "blockquote" then convert_quote_block(el)
      when "pre" then convert_preformatted(el)
      when "ul", "ol" then convert_list_element(el, 0)
      when "table" then convert_table_element(el)
      when "hr" then "'''"
      when "figure" then convert_figure(el)
      when "p", "div", "section", "article", "main", "span"
        if contains_block_content?(el)
          convert_block_children(el)
        else
          inline_content(el).presence
        end
      else
        if BLOCK_CONTAINER_TAGS.include?(tag)
          convert_block_children(el)
        else
          inline_content(el).presence
        end
      end
    end

    def contains_block_content?(el)
      el.element_children.any? do |child|
        tag = child.name.downcase
        BLOCK_CONTAINER_TAGS.include?(tag) || tag.match?(/\Ah[1-6]\z/)
      end
    end

    def convert_block_children(container)
      blocks = container.children.filter_map { |child| convert_top_level_node(child) }
      blocks.empty? ? nil : normalize_blocks(blocks)
    end

    def convert_quote_block(el)
      inner = convert_block_children(el) || inline_content(el)
      text = inner&.strip
      return nil if text.blank?

      "____\n#{text}\n____"
    end

    def convert_preformatted(el)
      code = el.at_css("code")
      source = code || el
      text = source.text.to_s.sub(/\n\z/, "")
      return nil if text.strip.blank?

      lang =
        code&.[]("data-lang") ||
        code&.[]("class")&.match(/(?:language|lang)-(\S+)/)&.[](1) ||
        ""

      lines = []
      lines << "[source,#{lang}]" if lang.present?
      lines.concat(["----", text, "----"])
      lines.join("\n")
    end

    def convert_list_element(list, depth)
      tag = list.name.downcase
      items = list.element_children.select { |child| child.name.casecmp("li").zero? }
      return nil if items.empty?

      items.each_with_index.filter_map do |item, index|
        marker = tag == "ol" ? ".#{index + 1}" : "*" * (depth + 1)
        convert_list_item(item, marker, depth)
      end.join("\n")
    end

    def convert_list_item(item, marker, depth)
      lines = []
      item_text = +""

      item.children.each do |child|
        if child.element?
          tag = child.name.downcase
          next if %w[ul ol].include?(tag)

          item_text << inline_content(child)
        elsif child.text?
          item_text << child.text
        end
      end

      trimmed = normalize_whitespace(item_text)
      lines << "#{marker} #{trimmed}" if trimmed.present?

      item.element_children.each do |nested|
        next unless %w[ul ol].include?(nested.name.downcase)

        nested_list = convert_list_element(nested, depth + 1)
        lines << nested_list if nested_list.present?
      end

      lines.reject(&:blank?).join("\n")
    end

    def convert_table_element(table)
      rows = table.css("tr")
      return nil if rows.empty?

      lines = ["|==="]
      rows.each do |row|
        cells = row.css("th, td")
        next if cells.empty?

        lines << "|#{cells.map { |cell| " #{inline_content(cell)} " }.join('|')}"
      end
      lines << "|==="
      lines.join("\n")
    end

    def convert_figure(figure)
      img = figure.at_css("img")
      caption = figure.at_css("figcaption")&.text&.strip
      if img
        image_line = convert_image_element(img)
        return "#{image_line}\n\n_#{caption}_" if image_line.present? && caption.present?
        return image_line if image_line.present?
      end

      convert_block_children(figure)
    end

    def convert_image_element(img)
      src = img["src"].to_s.strip
      alt = img["alt"].to_s.strip
      return alt if src.blank?

      if src.match?(/\Ahttps?:\/\//i)
        return "link:#{src}[#{escape_link_label(alt)}]" if alt.present?

        return src
      end

      return "image::#{src}[#{escape_link_label(alt)}]" if alt.present?

      "image::#{src}[]"
    end

    def inline_text(el)
      normalize_whitespace(inline_content(el))
    end

    def inline_content(node)
      node.children.map { |child| inline_node(child) }.join
    end

    def inline_node(node)
      case node
      when Nokogiri::XML::Text
        node.text
      when Nokogiri::XML::Element
        inline_element_node(node)
      else
        ""
      end
    end

    def inline_element_node(el)
      tag = el.name.downcase
      return "\n" if tag == "br"
      return convert_image_element(el) if tag == "img"

      inner = inline_content(el)
      return "" if inner.blank? && tag != "img"

      case tag
      when "strong", "b"
        inner.strip.present? ? "*#{inner.strip}*" : ""
      when "em", "i"
        inner.strip.present? ? "_#{inner.strip}_" : ""
      when "code", "kbd"
        inner.strip.present? ? "`#{inner.strip}`" : ""
      when "a"
        convert_anchor(el, inner)
      when "span", "font"
        inner
      else
        if tag.match?(/\Ah[1-6]\z/)
          inner.strip
        elsif BLOCK_CONTAINER_TAGS.include?(tag)
          convert_block_children(el) || inner
        else
          inner
        end
      end
    end

    def convert_anchor(el, inner)
      href = el["href"].to_s.strip
      return inner if href.blank?

      label = inner.strip
      if label.present? && label != href
        "link:#{href}[#{escape_link_label(label)}]"
      else
        href
      end
    end

    def normalize_whitespace(text)
      text.to_s.tr("\u00a0", " ").gsub(/[ \t]+\n/, "\n").gsub(/\n[ \t]+/, "\n").strip
    end

    def escape_link_label(text)
      text.gsub("\\", "\\\\").gsub("[", "\\[").gsub("]", "\\]")
    end
  end
end
