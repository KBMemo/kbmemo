# frozen_string_literal: true

namespace :kbmemo do
  namespace :embeddings do
    desc "Backfill memo embedding chunks (requires pgvector and embedding server)"
    task backfill: :environment do
      unless MemoEmbeddingChunk.pgvector_enabled?
        abort "pgvector is not enabled (memo_embedding_chunks.embedding column missing)."
      end

      indexer = Chat::Tools::MemoEmbeddingIndexer.new
      total = 0
      Memo.find_each do |memo|
        count = indexer.index_memo(memo)
        total += count
        print "." if (total % 10).zero?
      end
      puts "\nIndexed #{total} chunks."
    end
  end
end
