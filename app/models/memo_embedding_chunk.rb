# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_embedding_chunks
#
#  id          :bigint           not null, primary key
#  chunk_index :integer          default(0), not null
#  content     :text             not null
#  embedding   :vector(1024)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  memo_id     :bigint           not null
#
# Indexes
#
#  index_memo_embedding_chunks_on_embedding_hnsw           (embedding) USING hnsw
#  index_memo_embedding_chunks_on_memo_id                  (memo_id)
#  index_memo_embedding_chunks_on_memo_id_and_chunk_index  (memo_id,chunk_index) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (memo_id => memos.id)
#
class MemoEmbeddingChunk < ApplicationRecord
  EMBEDDING_DIMENSIONS = 1024

  belongs_to :memo

  validates :chunk_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :content, presence: true

  class << self
    def pgvector_enabled?
      return @pgvector_enabled if defined?(@pgvector_enabled)

      @pgvector_enabled = connection.column_exists?(:memo_embedding_chunks, :embedding)
    rescue StandardError
      @pgvector_enabled = false
    end

    def reset_pgvector_cache!
      remove_instance_variable(:@pgvector_enabled) if defined?(@pgvector_enabled)
    end

    def nearest_to(query_vector, memo_ids_scope:, limit:)
      return none unless pgvector_enabled?

      vector_sql = format_vector(query_vector)
      joins(:memo)
        .where(memo_id: memo_ids_scope.select(:id))
        .where.not(embedding: nil)
        .order(Arel.sql("embedding <=> #{connection.quote(vector_sql)}::vector"))
        .limit(limit)
    end

    def format_vector(values)
      "[#{Array(values).map { |v| Float(v) }.join(',')}]"
    end

    def upsert!(memo_id:, chunk_index:, content:, embedding: nil)
      record = find_or_initialize_by(memo_id: memo_id, chunk_index: chunk_index)
      record.content = content
      record.save!

      if pgvector_enabled? && embedding.present?
        connection.execute(
          sanitize_sql_array([
            "UPDATE memo_embedding_chunks SET embedding = ?::vector WHERE id = ?",
            format_vector(embedding),
            record.id
          ])
        )
      end

      record
    end

    def replace_for_memo!(memo_id, chunks)
      transaction do
        where(memo_id: memo_id).delete_all
        Array(chunks).each_with_index do |entry, index|
          upsert!(
            memo_id: memo_id,
            chunk_index: index,
            content: entry.fetch(:content),
            embedding: entry[:embedding]
          )
        end
      end
    end
  end
end
