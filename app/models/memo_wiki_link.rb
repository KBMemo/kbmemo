# frozen_string_literal: true

# メモ本文の Wiki リンク（[[...]] 等）を解決した結果の有向エッジ。
# source_memo が target_memo へリンクしていることを表す。
# == Schema Information
#
# Table name: memo_wiki_links
#
#  id             :integer          not null, primary key
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  source_memo_id :integer          not null
#  target_memo_id :integer          not null
#
# Indexes
#
#  index_memo_wiki_links_on_source_memo_id                     (source_memo_id)
#  index_memo_wiki_links_on_source_memo_id_and_target_memo_id  (source_memo_id,target_memo_id) UNIQUE
#  index_memo_wiki_links_on_target_memo_id                     (target_memo_id)
#
# Foreign Keys
#
#  source_memo_id  (source_memo_id => memos.id) ON DELETE => cascade
#  target_memo_id  (target_memo_id => memos.id) ON DELETE => cascade
#
class MemoWikiLink < ApplicationRecord
  belongs_to :source_memo, class_name: "Memo"
  belongs_to :target_memo, class_name: "Memo"

  validates :source_memo_id, uniqueness: { scope: :target_memo_id }
  validate :source_and_target_must_differ

  private

  def source_and_target_must_differ
    return if source_memo_id.blank? || target_memo_id.blank?
    return if source_memo_id != target_memo_id

    errors.add(:target_memo_id, "must differ from source")
  end
end
