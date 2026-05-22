# frozen_string_literal: true

# API クリップ用 HTML を Pandoc で AsciiDoc に変換し、画像をローカルアセットへ取り込む。
class ClipAsciidocProcessor
  class << self
    def call(html:, memo:, source_url: nil, plain: nil)
      source = html.to_s.strip
      source = plain_to_html(plain) if source.blank?

      prepared = ClipHtmlPreparer.prepare(source)
      return "" if prepared.blank?

      html_with_images = ClipImageImporter.new(memo, base_url: source_url).localize!(
        prepared,
        src_format: :filename
      )
      PandocHtmlToAsciidoc.convert(html_with_images).strip
    end

    private

    def plain_to_html(plain)
      text = plain.to_s.strip
      return "" if text.blank?

      escaped = ERB::Util.html_escape(text).gsub(/\r?\n/, "<br />\n")
      "<p>#{escaped}</p>"
    end
  end
end
