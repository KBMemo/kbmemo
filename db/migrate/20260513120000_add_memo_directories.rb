# frozen_string_literal: true

class AddMemoDirectories < ActiveRecord::Migration[8.1]
  class MemoDirectory < ActiveRecord::Base
    self.table_name = "memo_directories"
  end

  class Memo < ActiveRecord::Base
    self.table_name = "memos"
  end

  def up
    create_table :memo_directories do |t|
      t.string :path_segment, null: false, default: ""
      t.string :label, null: false, default: ""
      t.timestamps
    end
    add_index :memo_directories, :path_segment, unique: true

    add_reference :memos, :memo_directory, foreign_key: true, null: true

    root = MemoDirectory.create!(path_segment: "", label: "ルート")
    Memo.update_all(memo_directory_id: root.id)
    change_column_null :memos, :memo_directory_id, false

    remove_index :memos, :slug if index_exists?(:memos, :slug)
    add_index :memos, %i[memo_directory_id slug], unique: true
  end

  def down
    remove_index :memos, %i[memo_directory_id slug]
    add_index :memos, :slug, unique: true

    remove_reference :memos, :memo_directory, foreign_key: true
    drop_table :memo_directories
  end
end
