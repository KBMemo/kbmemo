# frozen_string_literal: true

# 本文エディタの [[...]] オートコンプリート候補（MemoWikiLinks の解決形式に合わせる）。
class MemoWikiCompletions
  MAX = 15

  def initialize(scope:, source_memo: nil)
    @scope = scope
    @source_memo = source_memo
  end

  def call(query)
    q = query.to_s.strip
    memos = ranked_memos(q).first(MAX)
    memos.flat_map { |memo| entries_for(memo) }.uniq { |e| e[:insert] }
  end

  private

  def ranked_memos(query)
    rel = @scope.includes(:memo_directory)
    rel = rel.where.not(id: @source_memo.id) if @source_memo&.persisted?

    if query.present?
      return rel.search_text(query).order(:title).to_a
    end

    ordered = rel.order(updated_at: :desc).limit(MAX * 3).to_a
    return ordered if @source_memo.blank?

    same_dir, other = ordered.partition { |m| m.memo_directory_id == @source_memo.memo_directory_id }
    (same_dir + other).first(MAX * 3)
  end

  def entries_for(memo)
    list = [
      { label: memo.title, insert: memo.title, detail: "タイトル" }
    ]
    slug = memo.slug.to_s
    if slug.present?
      list << { label: slug, insert: slug, detail: "スラッグ（全体で一意）" }
    end
    list
  end
end
