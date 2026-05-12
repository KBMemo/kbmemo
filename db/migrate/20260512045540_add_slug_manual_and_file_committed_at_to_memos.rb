class AddSlugManualAndFileCommittedAtToMemos < ActiveRecord::Migration[8.1]
  def change
    add_column :memos, :slug_manual, :boolean, default: false, null: false
    add_column :memos, :file_committed_at, :datetime
  end
end
