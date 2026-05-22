# frozen_string_literal: true

class ClipHtmlAttribution
  class << self
    def append(html, metadata)
      url = metadata.url.to_s.strip
      return html if url.blank?

      label = build_label(metadata.title, url)
      body = html.to_s.rstrip
      footer = %(<p><a href="#{escape_href(url)}">#{escape_html(label)}</a></p>)
      body.present? ? "#{body}\n\n#{footer}" : footer
    end

    private

    def build_label(title, _url)
      trimmed = title.to_s.strip
      trimmed.present? ? "出典: #{trimmed}" : "出典"
    end

    def escape_html(text)
      ERB::Util.html_escape(text)
    end

    def escape_href(url)
      ERB::Util.html_escape(url)
    end
  end
end
