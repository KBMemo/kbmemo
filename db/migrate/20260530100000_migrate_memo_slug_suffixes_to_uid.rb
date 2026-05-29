# frozen_string_literal: true

# スラッグ末尾の識別子を整数 id から uid（ULID）へ移行する。
# 生成は uid 採番後に before_validation で完結するため、作成後の slug 付け直しは不要になった。
class MigrateMemoSlugSuffixesToUid < ActiveRecord::Migration[8.1]
  def up
    say_with_time "rewriting memo slugs to uid suffixes" do
      count = 0
      Memo.reset_column_information
      Memo.unscoped.find_each do |memo|
        next if memo.uid.blank?

        stem = Memo.slug_stem(memo.slug, memo_id: memo.id, uid: memo.uid)
        target = Memo.global_slug_for(stem, memo.uid)
        next if memo.slug == target

        memo.update_column(:slug, target)
        count += 1
      end
      count
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
