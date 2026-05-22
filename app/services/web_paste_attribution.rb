# frozen_string_literal: true

# Append source link footer to AsciiDoc body (mirrors webPasteAttribution.js).
class WebPasteAttribution
  class << self
    def append(adoc, metadata)
      url = metadata.url.to_s.strip
      return adoc if url.blank?

      label = build_label(metadata.title, url)
      footer = "link:#{url}[#{escape_link_label(label)}]"
      body = adoc.to_s.rstrip
      body.present? ? "#{body}\n\n#{footer}" : footer
    end

    private

    def build_label(title, _url)
      trimmed = title.to_s.strip
      trimmed.present? ? "出典: #{trimmed}" : "出典"
    end

    def escape_link_label(text)
      text.gsub("\\", "\\\\").gsub("[", "\\[").gsub("]", "\\]")
    end
  end
end
