# frozen_string_literal: true

# メモ本文 AsciiDoc 内の [source,svg] … ---- ブロックの抽出・差し替え。
class MemoSvgSourceBlocks
  class Error < StandardError; end
  class NotFound < Error; end

  OPENING = /
    (?:\A|(?<=\n))
    (?<prefix>(?:\.[^\n]*\n)?\[source,\s*svg\s*\]\n----\n)
  /mx

  CLOSING = /\n(?<close>----+)\s*(?:\n|\z)/

  def self.normalize_text(text)
    Utf8Bytes.coerce(text).gsub(/\r\n?/, "\n")
  end

  def self.find_all(body)
    text = normalize_text(body)
    results = []
    pos = 0

    while (match = text.match(OPENING, pos))
      content_start = match.end(0)
      close_match = text.match(CLOSING, content_start)
      raise Error, "SVG ソースブロックが閉じられていません" unless close_match

      results << {
        index: results.size,
        prefix: match[:prefix],
        source: text[content_start...close_match.begin(0)],
        close: close_match[:close],
        range: match.begin(0)...close_match.end(0)
      }
      pos = close_match.end(0)
    end

    results
  end

  def self.fetch(body, index:)
    block = find_all(body)[index] or raise NotFound, "SVG ソースブロックが見つかりません"
    block[:source]
  end

  def self.replace(body, index:, new_source:)
    text = normalize_text(body)
    blocks = find_all(text)
    block = blocks[index] or raise NotFound, "SVG ソースブロックが見つかりません"

    sanitized = MemoSvgSanitizer.sanitize!(Utf8Bytes.coerce(new_source).strip)
    formatted = format_svg(sanitized)
    replacement = "#{block[:prefix]}#{formatted}\n#{block[:close]}\n"

    text[0...block[:range].begin] + replacement + text[block[:range].end..].to_s
  end

  def self.format_svg(svg)
    doc = Nokogiri::XML(svg) { |cfg| cfg.default_xml.noblanks }
    root = doc.root
    raise MemoAssets::InvalidFile, "SVG のルート要素が不正です" unless root&.name == "svg"

    root.to_xml(indent: 2).strip
  rescue Nokogiri::XML::SyntaxError
    raise MemoAssets::InvalidFile, "SVG の形式が不正です"
  end
  private_class_method :format_svg
end
