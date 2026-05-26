# frozen_string_literal: true

class CreateMemoWikiLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_wiki_links do |t|
      t.references :source_memo, null: false, foreign_key: { to_table: :memos, on_delete: :cascade }
      t.references :target_memo, null: false, foreign_key: { to_table: :memos, on_delete: :cascade }
      t.timestamps
    end

    add_index :memo_wiki_links, %i[source_memo_id target_memo_id], unique: true
  end
end
