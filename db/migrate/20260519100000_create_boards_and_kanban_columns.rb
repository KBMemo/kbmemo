# frozen_string_literal: true

class CreateBoardsAndKanbanColumns < ActiveRecord::Migration[8.1]
  def change
    create_table :boards do |t|
      t.references :account, null: false, foreign_key: true
      t.string :title, null: false
      t.references :memo_directory, null: true, foreign_key: true

      t.timestamps
    end

    create_table :board_columns do |t|
      t.references :board, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :board_columns, %i[board_id position], unique: true

    change_table :memos, bulk: true do |t|
      t.references :board, null: true, foreign_key: true
      t.references :kanban_column, null: true, foreign_key: { to_table: :board_columns }
      t.integer :kanban_position, null: false, default: 0
    end
  end
end
