# frozen_string_literal: true

# メモ本文の Wiki リンクを AsciiDoc の内部リンクへ展開する。
#   [[タイトル]] / [[タイトル|表示名]]
#   [[slug-{memo_id}]]（アプリ全体で一意なスラッグ。ディレクトリ移動の影響を受けない）
#   [[slug-{memo_id}|表示名]]
#   [[stem]] — レガシー: 末尾 -{id} なしの表記（同一 scope 内で stem が一意のときのみ）
#   [[full_path/slug-{id}]] — レガシー互換（スラッグ部分はグローバル解決を優先）
# 解決は policy_scope 済みの Relation のみを対象とする（閲覧不可のメモは存在しない扱い）。
class MemoWikiLinks
  LINK_PATTERN = /\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]/.freeze

  MemoRef = Data.define(:id, :memo_directory_id, :title)
  Resolved = Data.define(:id, :title, :by) # :title | :slug

  def initialize(scope:, source_memo: nil)
    @scope = scope
    @source_memo = source_memo
  end

  # エディタ WYSIWYG 用。policy_scope 内で target を解決する。
  def resolve_target(target)
    key = target.to_s.strip
    return nil if key.blank?

    resolve(key)
  end

  def substitute(text)
    return text if text.blank?

    out = +""
    in_fenced = false
    text.each_line do |line|
      if line.match?(/\A```/)
        in_fenced = !in_fenced
        out << line
      elsif in_fenced
        out << line
      else
        out << line.gsub(LINK_PATTERN) { replace_link(Regexp.last_match) }
      end
    end
    out
  end

  def self.extract_link_targets(text)
    return [] if text.blank?

    targets = []
    in_fenced = false
    text.each_line do |line|
      if line.match?(/\A```/)
        in_fenced = !in_fenced
      elsif !in_fenced
        line.scan(LINK_PATTERN) do
          targets << Regexp.last_match(1).strip
        end
      end
    end
    targets.uniq
  end

  private

  def replace_link(m)
    target = m[1].strip
    custom_label = m[2]&.strip.presence
    display_label = custom_label || target
    resolved = resolve(target)
    if resolved
      link_label = custom_label || link_display_label(resolved, target)
      "link:/memos/#{resolved.id}[#{escape_asciidoc_link_text(link_label)}]"
    else
      broken_link_markup(display_label)
    end
  end

  def broken_link_markup(label)
    # safe モードの Asciidoctor では HTML パススルーがエスケープされるため role 記法を使う
    "[.memo-wiki-broken]##{escape_asciidoc_unquoted(label)}#"
  end

  def escape_asciidoc_unquoted(text)
    text.to_s.gsub("#", '\\#')
  end

  def link_display_label(resolved, target)
    resolved.by == :slug ? resolved.title : target
  end

  def escape_asciidoc_link_text(text)
    text.to_s.gsub("]", "\\]")
  end

  def resolve(target)
    key = target.strip
    return nil if key.blank?

    load_index!

    if key.include?("/")
      path_slug = resolve_path_slug(key)
      return path_slug if path_slug
    end

    slug_key = key.downcase
    if (resolved = resolve_global_slug(slug_key))
      return resolved
    end

    if (resolved = resolve_slug_stem(slug_key))
      return resolved
    end

    title_key = normalize_title(key)
    if (refs = @titles_index[title_key])
      same_dir = refs.select { |r| r.memo_directory_id == source_directory_id }
      return resolved_from_ref(same_dir.first, :title) if same_dir.size == 1
      return resolved_from_ref(refs.first, :title) if refs.size == 1
    end

    nil
  end

  def resolved_from_ref(ref, by)
    Resolved.new(ref.id, ref.title, by)
  end

  def resolve_global_slug(slug_key)
    memo_id = @slug_by_key[slug_key]
    return nil unless memo_id

    Resolved.new(memo_id, @title_by_id[memo_id], :slug)
  end

  def resolve_slug_stem(stem_key)
    ids = @slug_stem_index[stem_key]
    return nil if ids.blank? || ids.size != 1

    memo_id = ids.first
    Resolved.new(memo_id, @title_by_id[memo_id], :slug)
  end

  def source_directory_id
    @source_memo&.memo_directory_id
  end

  def resolve_path_slug(target)
    _dir_part, _, slug_part = target.rpartition("/")
    slug_key = slug_part.strip.downcase
    return nil if slug_key.blank?

    if (resolved = resolve_global_slug(slug_key))
      return resolved
    end

    if (resolved = resolve_slug_stem(slug_key))
      return resolved
    end

    dir_part = target.rpartition("/").first
    dir_path = normalize_directory_full_path(dir_part)
    dir_id = @directory_ids_by_full_path[dir_path]
    return nil unless dir_id

    resolve_slug_in_directory(dir_id, slug_key)
  end

  def resolve_slug_in_directory(dir_id, slug_key)
    memo_id = @slug_by_directory[[ dir_id, slug_key ]]
    return nil unless memo_id

    Resolved.new(memo_id, @title_by_id[memo_id], :slug)
  end

  def normalize_directory_full_path(path)
    path.to_s.strip.sub(/\A\/+/, "").sub(/\/+\z/, "").downcase
  end

  def normalize_title(value)
    value.to_s.strip.downcase
  end

  def load_index!
    return if @loaded

    @titles_index = Hash.new { |h, k| h[k] = [] }
    @slug_by_key = {}
    @slug_stem_index = Hash.new { |h, k| h[k] = [] }
    @slug_by_directory = {}
    @title_by_id = {}
    @directory_ids_by_full_path = {}
    directory_ids = []
    @scope.pluck(:id, :title, :memo_directory_id, :slug).each do |id, title, dir_id, slug|
      directory_ids << dir_id
      @title_by_id[id] = title
      @titles_index[normalize_title(title)] << MemoRef.new(id, dir_id, title)
      next if slug.blank?

      slug_key = slug.downcase
      @slug_by_key[slug_key] = id
      stem = Memo.slug_stem(slug, memo_id: id).downcase
      @slug_stem_index[stem] << id unless @slug_stem_index[stem].include?(id)
      @slug_by_directory[[ dir_id, slug_key ]] = id
      @slug_by_directory[[ dir_id, stem ]] = id if stem != slug_key
    end
    MemoDirectory.where(id: directory_ids.uniq).pluck(:id, :full_path).each do |id, full_path|
      @directory_ids_by_full_path[normalize_directory_full_path(full_path)] = id
    end
    @loaded = true
  end
end
