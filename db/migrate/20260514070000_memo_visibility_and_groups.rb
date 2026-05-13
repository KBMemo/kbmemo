# frozen_string_literal: true

class MemoVisibilityAndGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_groups do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :memo_group_memberships do |t|
      t.references :memo_group, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.timestamps
    end
    add_index :memo_group_memberships, %i[memo_group_id account_id], unique: true

    add_reference :memos, :account, null: true, foreign_key: { to_table: :accounts }, index: true
    add_reference :memos, :memo_group, null: true, foreign_key: true, index: true
    add_column :memos, :visibility, :integer, null: false, default: 0

    reversible do |dir|
      dir.up do
        default_id = select_value("SELECT id FROM accounts ORDER BY id LIMIT 1")
        raise ActiveRecord::IrreversibleMigration, "accounts が空です。先にアカウントを作成してください。" if default_id.blank?

        execute <<~SQL.squish
          UPDATE memos
          SET account_id = #{connection.quote(default_id)},
              visibility = 0
          WHERE account_id IS NULL
        SQL
      end
    end

    change_column_null :memos, :account_id, false
  end
end
