# frozen_string_literal: true

# メモ本文から Wiki リンクを解決し、memo_wiki_links テーブルを更新する。
class MemoWikiLinkIndex
  # link:/memos/{id}[ と link:/memos/{uid}[（ULID）の双方を拾う。
  MEMO_HREF_PATTERN = /link:\/memos\/([0-9A-Za-z]+)\[/.freeze

  class << self
    def rebuild_for(memo)
      return unless memo.persisted?

      scope = resolution_scope_for(memo)
      resolver = MemoWikiLinks.new(scope: scope, source_memo: memo)
      target_ids = Set.new

      MemoWikiLinks.extract_link_targets(memo.body).each do |target|
        resolved = resolver.resolve_target(target)
        target_ids << resolved.id if resolved
      end

      extract_memo_hrefs(memo.body).each do |token|
        resolved_id = resolve_href_token(scope, token)
        target_ids << resolved_id if resolved_id
      end

      target_ids.delete(memo.id)
      replace_outgoing_links(memo.id, target_ids.to_a)
    end

    def rebuild_inbound_for(target_memo)
      return unless target_memo.persisted?

      source_ids = MemoWikiLink.where(target_memo_id: target_memo.id).pluck(:source_memo_id)
      source_ids.concat(candidate_source_ids_for(target_memo))
      source_ids.uniq.each do |source_id|
        source = Memo.find_by(id: source_id)
        rebuild_for(source) if source
      end
    end

    def rebuild_all
      Memo.find_each { |memo| rebuild_for(memo) }
    end

    def search_patterns_for(memo)
      patterns = []
      slug = memo.slug
      if slug.present?
        patterns << "[[#{slug}]]"
        patterns << "[[#{slug}|"
        stem = Memo.slug_stem(slug, memo_id: memo.id)
        if stem.present? && stem != slug
          patterns << "[[#{stem}]]"
          patterns << "[[#{stem}|"
        end
      end

      title = memo.title.to_s.strip
      if title.present?
        patterns << "[[#{title}]]"
        patterns << "[[#{title}|"
      end

      dir = memo.memo_directory
      if dir && slug.present? && !dir.root?
        path = dir.full_path
        patterns << "[[#{path}/#{slug}]]"
        patterns << "[[#{path}/#{slug}|"
        patterns << "[[/#{path}/#{slug}]]"
        patterns << "[[/#{path}/#{slug}|"
      end

      patterns << "link:/memos/#{memo.id}["
      patterns << "link:/memos/#{memo.uid}[" if memo.uid.present?

      patterns.uniq
    end

    private

    # link:/memos/{token}[ の token（数値 id または uid）を scope 内のメモ id へ解決する。
    def resolve_href_token(scope, token)
      if token.match?(/\A\d+\z/)
        id = token.to_i
        scope.exists?(id: id) ? id : nil
      else
        scope.where(uid: token.upcase).pick(:id)
      end
    end

    def resolution_scope_for(memo)
      MemoPolicy::Scope.new(memo.account, Memo.all).resolve
    end

    def replace_outgoing_links(source_memo_id, target_memo_ids)
      MemoWikiLink.transaction do
        MemoWikiLink.where(source_memo_id: source_memo_id).delete_all
        target_memo_ids.each do |target_memo_id|
          MemoWikiLink.create!(source_memo_id: source_memo_id, target_memo_id: target_memo_id)
        end
      end
    end

    def candidate_source_ids_for(target_memo)
      patterns = search_patterns_for(target_memo)
      return [] if patterns.empty?

      conditions = patterns.map { "LOWER(memos.body) LIKE ? ESCAPE '\\'" }.join(" OR ")
      Memo
        .where.not(id: target_memo.id)
        .where(conditions, *patterns.map { |pattern| like_pattern(pattern.downcase) })
        .pluck(:id)
    end

    def like_pattern(fragment)
      "%#{sanitize_like(fragment)}%"
    end

    def sanitize_like(value)
      value.to_s.gsub(/([\\%_])/, '\\\\\1')
    end

    def extract_memo_hrefs(text)
      return [] if text.blank?

      tokens = []
      in_fenced = false
      text.each_line do |line|
        if line.match?(/\A```/)
          in_fenced = !in_fenced
        elsif !in_fenced
          line.scan(MEMO_HREF_PATTERN) { tokens << Regexp.last_match(1) }
        end
      end
      tokens.uniq
    end
  end
end
