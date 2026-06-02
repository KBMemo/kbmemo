# frozen_string_literal: true

# album:: / image::media: を Tsuzura 署名 URL へ展開（表示・プレビュー用）。
class MemoTsuzuraMacro
  ALBUM_LINE = /\Aalbum::([0-9A-HJKMNP-TV-Z]{26})(\[[^\]]*\])?\s*\z/i
  MEDIA_IMAGE = /image::media:([0-9A-HJKMNP-TV-Z]{26})(\[[^\]]*\])?/
  LEGACY_SIGNED_IMAGE = Tsuzura::MediaUrlSigner::LEGACY_SIGNED_IMAGE

  def initialize(memo:, viewer: nil)
    @memo = memo
    @authorizer = Tsuzura::Authorizer.new(memo: memo, viewer: viewer) if memo&.persisted?
  end

  def substitute(text)
    return text if text.blank? || !@memo&.persisted? || !@authorizer&.allowed?

    out = +""
    in_fenced = false
    text.each_line do |line|
      if line.match?(/\A```/)
        in_fenced = !in_fenced
        out << line
      elsif in_fenced
        out << line
      else
        out << substitute_tsuzura_on_line(line)
      end
    end
    out
  end

  private

  def substitute_tsuzura_on_line(line)
    nl = line.end_with?("\n") ? "\n" : ""
    body = line.chomp

    if (m = body.match(ALBUM_LINE))
      return "#{replace_album(m[1])}#{nl}"
    end

    body = body.gsub(LEGACY_SIGNED_IMAGE) do
      replace_media(Regexp.last_match(1), Regexp.last_match(2).to_s)
    end
    body.gsub(MEDIA_IMAGE) do
      replace_media(Regexp.last_match(1), Regexp.last_match(2).to_s)
    end + nl
  end

  def replace_album(ulid)
    album = Tsuzura::Client.fetch_album(ulid)
    return missing_markup("album", ulid) unless album

    ids = Array(album["media_item_ids"]).first(24)
    return missing_markup("album", ulid) if ids.empty?

    ids.map { |id| replace_media(id, "[]") }.join("\n")
  end

  def replace_media(ulid, attrs)
    normalized = ulid.to_s.strip.upcase
    url = @authorizer.sign_media_url(normalized)
    return missing_markup("media", normalized) unless url

    "image::#{url}#{attrs.presence || '[]'}"
  end

  def missing_markup(kind, label)
    "[.tsuzura-missing]##{escape("#{kind}:#{label}")}#"
  end

  def escape(text)
    text.to_s.gsub("#", '\\#')
  end
end
