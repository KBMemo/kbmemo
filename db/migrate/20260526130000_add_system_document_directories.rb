# frozen_string_literal: true

class AddSystemDocumentDirectories < ActiveRecord::Migration[8.1]
  def up
    MemoDirectory::SystemSpace.ensure_buckets!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "system bucket directories are required"
  end
end
