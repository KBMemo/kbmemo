# frozen_string_literal: true

# HTML フラグメントを Pandoc で AsciiDoc に変換する。
class PandocHtmlToAsciidoc
  class << self
    def convert(html)
      trimmed = WebPasteMetadata.strip_kbmemo_comment(html.to_s.strip)
      return "" if trimmed.blank?

      PandocRunner.convert(
        from: "html",
        to: "asciidoc",
        input: trimmed,
        extra_args: [ "--wrap=none" ]
      ).strip
    end
  end
end
