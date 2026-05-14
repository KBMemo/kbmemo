# frozen_string_literal: true

class MemoDirectoryParentFullPathBuckets < ActiveRecord::Migration[8.1]
  def up
    add_reference :memo_directories, :parent, null: true, foreign_key: { to_table: :memo_directories }
    add_column :memo_directories, :full_path, :string

    remove_index :memo_directories, name: "index_memo_directories_on_path_segment"

    say_with_time "backfill memo_directories parent and full_path" do
      root = MemoDirectory.find_by!(path_segment: "")
      root.update_columns(parent_id: nil, full_path: "")
      MemoDirectory.where.not(id: root.id).find_each do |d|
        d.update_columns(parent_id: root.id, full_path: d.path_segment)
      end
    end

    change_column_null :memo_directories, :full_path, false
    add_index :memo_directories, :full_path, unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "memo directory tree migration cannot be safely reversed"
  end
end
