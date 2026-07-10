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

      test "index_memo splits oversize chunks and continues indexing" do
        skip "pgvector not enabled" unless MemoEmbeddingChunk.pgvector_enabled?

        calls = []
        client = Object.new
        client.define_singleton_method(:embed) do |text, kind: :document|
          calls << text
          raise Chat::EmbeddingClient::Error, "input is too large to process" if text.length > 250

          Array.new(MemoEmbeddingChunk::EMBEDDING_DIMENSIONS) { 0.1 }
        end

        memo = memos(:one)
        memo.update_columns(title: "T", body: "x" * 500)

        count = MemoEmbeddingIndexer.new(embedding_client: client).index_memo(memo)

        assert_operator count, :>, 1
        assert calls.all? { |text| text.length <= 250 }
      end

      test "index_memo returns zero on embedding error without raising" do
        skip "pgvector not enabled" unless MemoEmbeddingChunk.pgvector_enabled?

        client = Object.new
        client.define_singleton_method(:embed) { |*_args, **_kwargs| raise Chat::EmbeddingClient::Error, "down" }

        assert_equal 0, MemoEmbeddingIndexer.new(embedding_client: client).index_memo(memos(:one))
      end
    end
  end
end
