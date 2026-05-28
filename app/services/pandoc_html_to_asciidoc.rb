# frozen_string_literal: true

# HTML フラグメントを Pandoc で AsciiDoc に変換する。
class PandocHtmlToAsciidoc
  # Pandoc が HTML class を AsciiDoc role 記法へ写すと、隣接 span で Asciidoctor が誤パースする。
  PANDOC_INLINE_ROLE = /\[\.[^\]]+\]#([^#\n]+?)#/

  class << self
    def convert(html)
      trimmed = WebPasteMetadata.strip_kbmemo_comment(html.to_s.strip)
      return "" if trimmed.blank?

      normalize_output(
        PandocRunner.convert(
          from: "html",
          to: "asciidoc",
          input: trimmed,
          extra_args: [ "--wrap=none" ]
        )
      )
    end

    def normalize_output(adoc)
      adoc.to_s
          .gsub(/^\[\.[^\]]+\]\n(?=\S)/, "")
          .gsub(PANDOC_INLINE_ROLE, '\1')
          .strip
    end
  end
end
