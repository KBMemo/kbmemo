# frozen_string_literal: true

module Chat
  module Tools
    # メモ本文チャンクを LFM2.5-Embedding でベクトル化し memo_embedding_chunks に保存する。
    class MemoEmbeddingIndexer
      MIN_SPLIT_CHARS = 200

      def initialize(embedding_client: nil, chunker: Chat::MemoChunker.new)
        @embedding_client = embedding_client
        @chunker = chunker
      end

      # @param memo [Memo]
      # @return [Integer] 保存したチャンク数
      def index_memo(memo)
        return 0 unless MemoEmbeddingChunk.pgvector_enabled?

        texts = @chunker.chunk(title: memo.title, body: memo.body)
        return MemoEmbeddingChunk.where(memo_id: memo.id).delete_all if texts.empty?

        chunks = texts.flat_map { |text| embed_text_chunks(text, account: memo.account) }
        return 0 if chunks.empty?

        MemoEmbeddingChunk.replace_for_memo!(memo.id, chunks)
        chunks.size
      rescue Chat::EmbeddingClient::ConnectionError, Chat::EmbeddingClient::Error => e
        Rails.logger.warn("[MemoEmbeddingIndexer] memo=#{memo.id} #{e.message}")
        0
      end

      private

      def embed_text_chunks(text, account:, max_chars: Chat::MemoChunker::DEFAULT_MAX_CHARS)
        client = embedding_client(account: account)
        [ { content: text, embedding: client.embed(text, kind: :document) } ]
      rescue Chat::EmbeddingClient::Error => e
        raise unless oversize_error?(e) && text.length > MIN_SPLIT_CHARS

        next_limit = [ max_chars / 2, MIN_SPLIT_CHARS ].max
        raise if next_limit >= text.length

        @chunker.chunk(title: "", body: text, max_chars: next_limit).flat_map do |piece|
          embed_text_chunks(piece, account: account, max_chars: next_limit)
        end
      end

      def oversize_error?(error)
        error.message.match?(/too large to process/i)
      end

      def embedding_client(account: nil)
        @embedding_client || Chat::ModelRegistry.for(:embedding, account: account).build_embedding_client
      end
    end
  end
end
