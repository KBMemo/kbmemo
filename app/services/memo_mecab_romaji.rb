# frozen_string_literal: true

require "natto"
require "romaji"

# MeCab（読みは辞書の CSV・フィールド数は ipadic 系を想定）で読みを取り、romaji gem でヘボン式風の ASCII にしたうえでスラッグ断片にする。
# libmecab / 辞書が無い環境では例外となり、Memo は memo-{id} などへフォールバックする。
class MemoMecabRomaji
  class << self
    # @return [String, nil] ASCII のスラッグ断片、失敗時は nil
    def romaji_slug_from(text)
      raw = text.to_s.strip
      return nil if raw.blank?

      nm = Natto::MeCab.new
      parts = []

      nm.parse(raw) do |n|
        next if n.is_eos?

        feat = n.feature.split(",")
        romaji_part = morpheme_to_romaji(n.surface, feat)
        parts << romaji_part if romaji_part.present?
      end

      joined = parts.join("-")
      slugify(joined)
    rescue LoadError, Natto::MeCabError, StandardError
      nil
    end

    private

    # ipadic 全文フィールドは読みが index 7（カタカナ）、原型が 6。短い出力では読みが無いことがある。
    def morpheme_to_romaji(surface, feat)
      if feat.size >= 9
        yomi = feat[7].to_s
        yomi = feat[6].to_s if yomi.blank? || yomi == "*"
        if yomi.present? && yomi != "*"
          return Romaji.kana2romaji(yomi).downcase.presence
        end
      end

      if surface.match?(/\A[A-Za-z0-9]+\z/)
        return surface.downcase
      end

      nil
    end

    def slugify(asciiish)
      s = asciiish.to_s.downcase
      s = s.gsub(/[^a-z0-9]+/, "-")
      s.gsub(/^-+|-+$/, "").presence
    end
  end
end
