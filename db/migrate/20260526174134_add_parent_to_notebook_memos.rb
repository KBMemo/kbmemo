class AddParentToNotebookMemos < ActiveRecord::Migration[8.1]
  def change
    add_reference :notebook_memos, :parent, foreign_key: { to_table: :notebook_memos }, null: true

    remove_index :notebook_memos, column: %i[notebook_id position], if_exists: true
    add_index :notebook_memos, %i[notebook_id parent_id position], name: "index_notebook_memos_on_notebook_parent_position"
  end
end
