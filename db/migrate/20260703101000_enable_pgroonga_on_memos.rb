# frozen_string_literal: true

class EnablePgroongaOnMemos < ActiveRecord::Migration[8.1]
  INDEX_NAME = "index_memos_on_title_body_pgroonga"

  def up
    return unless pgroonga_available?

    enable_extension "pgroonga" unless extension_enabled?("pgroonga")
    return if pgroonga_index_exists?

    execute <<~SQL.squish
      CREATE INDEX #{INDEX_NAME}
      ON memos
      USING pgroonga ((title || E'\\n' || body))
    SQL
  end

  def down
    return unless extension_enabled?("pgroonga")

    execute "DROP INDEX IF EXISTS #{INDEX_NAME}"
    disable_extension "pgroonga"
  end

  private

  def pgroonga_available?
    select_value(<<~SQL.squish)
      SELECT EXISTS(
        SELECT 1 FROM pg_available_extensions WHERE name = 'pgroonga'
      )
    SQL
  end

  def pgroonga_index_exists?
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_indexes
      WHERE tablename = 'memos' AND indexname = '#{INDEX_NAME}'
    SQL
  end
end
