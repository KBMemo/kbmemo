# frozen_string_literal: true

class AddViewSequenceToMemoViewHistories < ActiveRecord::Migration[8.1]
  class MemoViewHistory < ActiveRecord::Base
    self.table_name = "memo_view_histories"
  end

  def up
    add_column :memo_view_histories, :view_sequence, :bigint

    say_with_time "backfill view_sequence" do
      MemoViewHistory.reset_column_information
      account_ids = MemoViewHistory.distinct.pluck(:account_id)
      account_ids.each do |account_id|
        MemoViewHistory.where(account_id: account_id)
          .order(viewed_at: :asc, id: :asc)
          .each_with_index do |entry, index|
            entry.update_column(:view_sequence, index + 1)
          end
      end
    end

    change_column_null :memo_view_histories, :view_sequence, false
    add_index :memo_view_histories, %i[account_id view_sequence],
      order: { view_sequence: :desc },
      name: "index_memo_view_histories_on_account_id_and_view_sequence"
  end

  def down
    remove_index :memo_view_histories, name: "index_memo_view_histories_on_account_id_and_view_sequence"
    remove_column :memo_view_histories, :view_sequence
  end
end
