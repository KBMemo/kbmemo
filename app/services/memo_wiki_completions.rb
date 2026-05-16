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
    return list if slug.blank?

    if @source_memo&.memo_directory_id == memo.memo_directory_id
      list << { label: slug, insert: slug, detail: "slug（同じディレクトリ）" }
    end

    path = wiki_link_path_for(memo)
    list << { label: path, insert: path, detail: "フルパス" } if path.present?

    list
  end

  def wiki_link_path_for(memo)
    dir = memo.memo_directory
    return nil if dir.nil? || dir.root?

    seg = Memo.normalize_slug_fragment(memo.slug)
    return nil if seg.blank?

    dir_path = dir.full_path.to_s.strip.sub(/\A\/+/, "").sub(/\/+\z/, "")
    dir_path.present? ? "#{dir_path}/#{seg}" : seg
  end
end
