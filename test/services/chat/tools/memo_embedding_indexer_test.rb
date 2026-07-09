# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class MemoEmbeddingIndexerTest < ActiveSupport::TestCase
      class StubEmbeddingClient
        def embed(text, kind: :document)
          Array.new(MemoEmbeddingChunk::EMBEDDING_DIMENSIONS) { text.length.to_f / 100.0 }
        end
      end

      test "index_memo stores chunks when pgvector enabled" do
        skip "pgvector not enabled" unless MemoEmbeddingChunk.pgvector_enabled?

        memo = memos(:one)
        memo.update_columns(title: "Idx", body: "Body for indexing")

        count = MemoEmbeddingIndexer.new(embedding_client: StubEmbeddingClient.new).index_memo(memo)

        assert_operator count, :>, 0
        assert_equal count, MemoEmbeddingChunk.where(memo_id: memo.id).count
      end

      test "index_memo returns zero when pgvector disabled" do
        MemoEmbeddingChunk.stub(:pgvector_enabled?, false) do
          count = MemoEmbeddingIndexer.new(embedding_client: StubEmbeddingClient.new).index_memo(memos(:one))
          assert_equal 0, count
        end
      end
    end
  end
end
