# frozen_string_literal: true

# 指定メモへ Wiki リンクしているメモ（バックリンク）を policy_scope 内から返す。
# リンク解決結果は memo_wiki_links テーブル（MemoWikiLinkIndex）を参照する。
class MemoWikiBacklinks
  def initialize(target_memo:, scope:)
    @target = target_memo
    @scope = scope
  end

  def call
    return [] unless @target.persisted?

    ids = link_source_ids
    return [] if ids.empty?

    @scope
      .where(id: ids)
      .includes(:account, :memo_directory, :tags)
      .sort_by { |memo| [ -memo.updated_at.to_i, memo.title.downcase ] }
  end

  private

  def link_source_ids
    @scope
      .where.not(id: @target.id)
      .joins(:outgoing_wiki_links)
      .where(memo_wiki_links: { target_memo_id: @target.id })
      .distinct
      .pluck(:id)
  end
end
