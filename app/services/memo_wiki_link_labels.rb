# frozen_string_literal: true

# 本文エディタの [[target]] / link:target / <<target>> 等の WYSIWYG 用ラベル（スラッグ解決時はタイトル）。
class MemoWikiLinkLabels
  MAX_TARGETS = 100

  def initialize(scope:, source_memo: nil)
    @resolver = MemoWikiLinks.new(scope: scope, source_memo: source_memo)
  end

  def call(targets)
    list = Array(targets).map { |t| t.to_s.strip }.reject(&:blank?).uniq.first(MAX_TARGETS)
    list.index_with { |target| entry_for(target) }
  end

  private

  def entry_for(target)
    resolved = @resolver.resolve_target(target)
    if resolved
      slug_based = resolved.by == :slug
      {
        display: slug_based ? resolved.title : target,
        resolved: true,
        slug: slug_based,
        memo_id: resolved.id
      }
    else
      {
        display: target,
        resolved: false,
        slug: false,
        memo_id: nil
      }
    end
  end
end
