# frozen_string_literal: true

# メモにクライアント生成可能な安定識別子 uid（ULID）を追加する。
# オフライン作成時に端末側で採番でき、同期は uid をキーにした upsert で冪等になる。
# 既存行は created_at を基準に ULID を採番し、作成順とソート順を揃える。
class AddUidToMemos < ActiveRecord::Migration[8.1]
  def up
    add_column :memos, :uid, :string

    say_with_time "backfilling memos.uid with ULIDs" do
      count = 0
      Memo.reset_column_information
      Memo.unscoped.order(:id).find_each do |memo|
        moment = memo.created_at || memo.updated_at || Time.current
        memo.update_column(:uid, ULID.generate(moment: moment).to_s)
        count += 1
      end
      count
    end

    change_column_null :memos, :uid, false
    add_index :memos, :uid, unique: true
  end

  def down
    remove_index :memos, :uid
    remove_column :memos, :uid
  end
end
