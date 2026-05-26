# frozen_string_literal: true

class CreateMemoViewHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_view_histories do |t|
      t.references :account, null: false, foreign_key: true
      t.references :memo, null: false, foreign_key: true
      t.datetime :viewed_at, null: false
      t.timestamps
    end

    add_index :memo_view_histories, %i[account_id memo_id], unique: true
    add_index :memo_view_histories, %i[account_id viewed_at]
  end
end
