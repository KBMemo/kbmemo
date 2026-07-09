# frozen_string_literal: true

class CreateMemoEmbeddingChunks < ActiveRecord::Migration[8.1]
  TABLE = "memo_embedding_chunks"
  VECTOR_INDEX = "index_memo_embedding_chunks_on_embedding_hnsw"

  def up
    create_table :memo_embedding_chunks do |t|
      t.references :memo, null: false, foreign_key: true
      t.integer :chunk_index, null: false, default: 0
      t.text :content, null: false
      t.timestamps
    end

    add_index :memo_embedding_chunks, %i[memo_id chunk_index], unique: true

    return unless pgvector_available?

    enable_extension "vector" unless extension_enabled?("vector")
    execute "ALTER TABLE #{TABLE} ADD COLUMN embedding vector(1024)"

    execute <<~SQL.squish
      CREATE INDEX #{VECTOR_INDEX}
      ON #{TABLE}
      USING hnsw (embedding vector_cosine_ops)
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS #{VECTOR_INDEX}" if vector_index_exists?
    drop_table :memo_embedding_chunks, if_exists: true
    disable_extension "vector" if extension_enabled?("vector")
  end

  private

  def pgvector_available?
    select_value(<<~SQL.squish)
      SELECT EXISTS(
        SELECT 1 FROM pg_available_extensions WHERE name = 'vector'
      )
    SQL
  end

  def vector_index_exists?
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_indexes
      WHERE tablename = '#{TABLE}' AND indexname = '#{VECTOR_INDEX}'
    SQL
  end
end
