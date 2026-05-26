# frozen_string_literal: true

class CreateNotebooks < ActiveRecord::Migration[8.1]
  def change
    create_table :notebooks do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.integer :publication_kind, null: false, default: 2
      t.datetime :published_at
      t.text :description, null: false, default: ""
      t.references :memo_directory, foreign_key: true
      t.timestamps
    end

    add_index :notebooks, %i[account_id slug], unique: true
    add_index :notebooks, %i[account_id publication_kind]

    create_table :notebook_memos do |t|
      t.references :notebook, null: false, foreign_key: true
      t.references :memo, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :chapter_title
      t.timestamps
    end

    add_index :notebook_memos, %i[notebook_id memo_id], unique: true
    add_index :notebook_memos, %i[notebook_id position]
  end
end
