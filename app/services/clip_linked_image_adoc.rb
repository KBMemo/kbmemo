# frozen_string_literal: true

# <a href="…"><img …></a> を AsciiDoc の link 付き image マクロへ整形する。
class ClipLinkedImageAdoc
  class << self
    def format(src:, alt: "", link: "")
      src = src.to_s.strip
      link = link.to_s.strip
      return "" if src.blank?

      prefix = src.match?(%r{\Ahttps?://}i) ? "image:" : "image::"
      "#{prefix}#{src}#{attribute_list(alt: alt.to_s, link: link)}"
    end

    private

    def attribute_list(alt:, link:)
      parts = []
      parts << quote_alt(escape_alt(alt)) if alt.present?
      parts << "link=#{link}" if link.present?
      return "[]" if parts.empty?

      "[#{parts.join(', ')}]"
    end

    def escape_alt(text)
      text.gsub("\\", "\\\\").gsub("[", "\\[").gsub("]", "\\]")
    end

    def quote_alt(text)
      return text unless text.match?(/[,"]/)

      %("#{text.gsub('"', '""')}")
    end
  end
end
