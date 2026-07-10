# frozen_string_literal: true

module Chat
  # メモ本文を埋め込み用チャンクに分割する（LFM2.5-Embedding の short-context 向け）。
  class MemoChunker
    # LFM2.5-Embedding の llama-server 既定 batch（512 tokens）に収める目安。
    # 日本語混在本文はおおよそ 2 chars/token 想定で余裕を見る。
    DEFAULT_MAX_CHARS = 480
    MIN_CHUNK_CHARS = 120

    DATA_URI_PATTERN = /data:image\/[a-zA-Z0-9.+_-]+;base64,[A-Za-z0-9+\/=]+/m
    EMBEDDED_IMAGE_PATTERN = /image:data:image\/[^;\s]+;base64,[A-Za-z0-9+\/=]+/m
    LONG_TOKEN_PATTERN = /\S{300,}/

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

    def chunk(title:, body:, max_chars: nil)
      limit = positive_max_chars(max_chars || @max_chars)
      parts = []
      header = title.to_s.strip
      parts << header if header.present?

      text = sanitize_for_embedding(body)
      return parts if text.blank?

      paragraphs = text.split(/\n{2,}/)
      buffer = ""

      paragraphs.each do |paragraph|
        piece = paragraph.strip
        next if piece.blank?

        candidate = buffer.blank? ? piece : "#{buffer}\n\n#{piece}"
        if candidate.length <= limit
          buffer = candidate
          next
        end

        parts << buffer if buffer.present?
        buffer = split_oversized(piece, parts, limit: limit)
      end

      parts << buffer if buffer.present?
      parts.presence || [ text[0, limit] ]
    end

    # base64 画像や極端に長い1行は埋め込み向きテキストから除外する。
    def sanitize_for_embedding(text)
      sanitized = text.to_s
        .gsub(EMBEDDED_IMAGE_PATTERN, "[image]")
        .gsub(DATA_URI_PATTERN, "[image]")
      sanitized.gsub(LONG_TOKEN_PATTERN) { |blob| "#{blob[0, 120]}…[truncated]" }
    end

    private

    def split_oversized(text, parts, limit:)
      remaining = text
      while remaining.length > limit
        parts << remaining[0, limit]
        remaining = remaining[limit..]
      end
      remaining
    end

    def positive_max_chars(value)
      [ value.to_i, MIN_CHUNK_CHARS ].max
    end
  end
end
