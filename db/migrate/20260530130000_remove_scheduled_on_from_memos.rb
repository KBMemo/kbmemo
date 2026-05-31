# frozen_string_literal: true

class RemoveScheduledOnFromMemos < ActiveRecord::Migration[8.0]
  def up
    return unless column_exists?(:memos, :scheduled_on)

    remove_index :memos, %i[board_id scheduled_on], if_exists: true
    remove_column :memos, :scheduled_on, :date
  end

  def down
    return if column_exists?(:memos, :scheduled_on)

    add_column :memos, :scheduled_on, :date
    add_index :memos, %i[board_id scheduled_on]
  end
end
