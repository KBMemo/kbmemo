# frozen_string_literal: true

# Markdown を Pandoc で AsciiDoc に変換する（API 書込 body_format=markdown 用）。
class PandocMarkdownToAsciidoc
  class << self
    def convert(markdown)
      text = markdown.to_s.strip
      return "" if text.blank?

      PandocHtmlToAsciidoc.normalize_output(
        PandocRunner.convert(
          from: "markdown",
          to: "asciidoc",
          input: text,
          extra_args: [ "--wrap=none" ]
        )
      )
    end
  end
end
