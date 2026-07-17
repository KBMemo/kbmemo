# frozen_string_literal: true

class CreateMemoDeletionRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_deletion_records do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :memo_id, null: false
      t.string :memo_uid, null: false
      t.datetime :deleted_at, null: false
      t.timestamps

      t.index [ :account_id, :deleted_at, :id ]
      t.index [ :account_id, :memo_uid ], unique: true
    end
  end
end
