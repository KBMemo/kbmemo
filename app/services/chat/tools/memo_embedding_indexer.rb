# frozen_string_literal: true

module Chat
  module Tools
    # メモ本文チャンクを LFM2.5-Embedding でベクトル化し memo_embedding_chunks に保存する。
    class MemoEmbeddingIndexer
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

        chunks = texts.map do |text|
          { content: text, embedding: client.embed(text, kind: :document) }
        end

        MemoEmbeddingChunk.replace_for_memo!(memo.id, chunks)
        chunks.size
      rescue Chat::EmbeddingClient::ConnectionError => e
        Rails.logger.warn("[MemoEmbeddingIndexer] memo=#{memo.id} #{e.message}")
        0
      end

      private

      def client
        @embedding_client ||= Chat::ModelRegistry.for(:embedding).build_embedding_client
      end
    end
  end
end
