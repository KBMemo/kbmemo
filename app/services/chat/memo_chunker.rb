# frozen_string_literal: true

module Chat
  # メモ本文を埋め込み用チャンクに分割する（LFM2.5-Embedding の short-context 向け）。
  class MemoChunker
    DEFAULT_MAX_CHARS = 1_800

    # @param title [String]
    # @param body [String]
    # @param max_chars [Integer]
    # @return [Array<String>]
    def self.chunk(title:, body:, max_chars: DEFAULT_MAX_CHARS)
      new(max_chars: max_chars).chunk(title: title, body: body)
    end

    def initialize(max_chars: DEFAULT_MAX_CHARS)
      @max_chars = max_chars
    end

    def chunk(title:, body:)
      parts = []
      header = title.to_s.strip
      parts << header if header.present?

      text = body.to_s.strip
      return parts if text.blank?

      paragraphs = text.split(/\n{2,}/)
      buffer = ""

      paragraphs.each do |paragraph|
        piece = paragraph.strip
        next if piece.blank?

        candidate = buffer.blank? ? piece : "#{buffer}\n\n#{piece}"
        if candidate.length <= @max_chars
          buffer = candidate
          next
        end

        parts << buffer if buffer.present?
        buffer = split_oversized(piece, parts)
      end

      parts << buffer if buffer.present?
      parts.presence || [ text[0, @max_chars] ]
    end

    private

    def split_oversized(text, parts)
      remaining = text
      while remaining.length > @max_chars
        parts << remaining[0, @max_chars]
        remaining = remaining[@max_chars..]
      end
      remaining
    end
  end
end
