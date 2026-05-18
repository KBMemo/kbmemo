module MemosHelper
  MEMO_VISIBILITY_LABELS = {
    "public_everyone" => "全体（未ログインでも閲覧可）",
    "group_read" => "グループ内のみ閲覧",
    "group_read_write" => "グループ内で読み書き",
    "owner_read_write" => "自分のみ読み書き"
  }.freeze

  def memo_directories_for_select
    policy_scope(MemoDirectory).nav_ordered
  end

  def memo_visibility_options_for_select
    Memo.visibilities.keys.map { |key| [ MEMO_VISIBILITY_LABELS.fetch(key, key.humanize), key ] }
  end

  # :new = 新規フォーム表示中, Integer = そのメモが選択中, nil = 一覧のみ（トップ）
  def memo_sidebar_highlight
    if %w[new create].include?(controller.action_name) && (!instance_variable_defined?(:@memo) || @memo.nil? || !@memo.persisted?)
      :new
    elsif instance_variable_defined?(:@memo) && @memo&.persisted?
      @memo.id
    else
      nil
    end
  end

  def memo_sidebar_selected?(key)
    memo_sidebar_highlight == key
  end

  def memo_sidebar_link_classes(key)
    base = "block border-l-2 px-3 py-3 text-sm transition focus:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400 focus-visible:ring-offset-2"
    if memo_sidebar_selected?(key)
      "#{base} border-l-zinc-900 bg-zinc-100 text-zinc-900"
    else
      "#{base} border-l-transparent hover:bg-zinc-50"
    end
  end

  # メモ一覧の行（グリップ＋リンク）用。左ボーダーで選択中を示す。
  def memo_sidebar_memo_list_row_classes(memo_id)
    base = "flex min-w-0 flex-1 items-stretch border-l-2 text-sm transition"
    if memo_sidebar_selected?(memo_id)
      "#{base} border-l-zinc-900 bg-zinc-100 text-zinc-900"
    else
      "#{base} border-l-transparent hover:bg-zinc-50"
    end
  end

  # 一覧のメモ行: ドラフト表示中は編集、確定のみ show へ（サイドバー表示モードをクエリで維持）
  def memo_sidebar_memo_main_href(memo)
    q = memo_sidebar_nav_query
    if memo.display_as_draft?
      q.present? ? edit_memo_path(memo, q) : edit_memo_path(memo)
    else
      q.present? ? memo_path(memo, q) : memo_path(memo)
    end
  end

  # ディレクトリ / タグ切り替え後も一覧・編集の文脈を保つクエリ（ハッシュ）
  def memo_sidebar_nav_query
    h = {}
    if defined?(@sidebar_view) && @sidebar_view == "search"
      h[:sidebar_view] = "search"
      h[:q] = @memo_search_query if defined?(@memo_search_query) && @memo_search_query.present?
    elsif defined?(@sidebar_view) && @sidebar_view == "tag"
      h[:sidebar_view] = "tag"
      tid = (@current_tag&.id || params[:tag_id]).presence
      h[:tag_id] = tid if tid
    elsif defined?(@current_memo_directory) && @current_memo_directory && !@current_memo_directory.root?
      h[:memo_directory_id] = @current_memo_directory.id
    end
    h
  end

  # show / edit 中はメモを開いたままサイドバー文脈だけ切り替える
  def memo_sidebar_open_memo
    return unless defined?(@memo) && @memo&.persisted?
    return unless %w[show edit].include?(controller.action_name)

    @memo
  end

  def memo_sidebar_open_memo_path(memo, query = {})
    if memo.display_as_draft?
      edit_memo_path(memo, query)
    else
      memo_path(memo, query)
    end
  end

  def memos_sidebar_directory_tab_path
    if (memo = memo_sidebar_open_memo)
      q = {}
      dir = memo.memo_directory
      q[:memo_directory_id] = dir.id unless dir.nil? || dir.root?
      return memo_sidebar_open_memo_path(memo, q)
    end

    return memos_path unless defined?(@current_memo_directory) && @current_memo_directory
    return memos_path if @current_memo_directory.root?

    memos_path(memo_directory_id: @current_memo_directory.id)
  end

  def memos_sidebar_tag_tab_path
    if (memo = memo_sidebar_open_memo)
      q = { sidebar_view: "tag" }
      tag = memo.tags.order(:name).first
      q[:tag_id] = tag.id if tag
      return memo_sidebar_open_memo_path(memo, q)
    end

    first = Tag.order(:name).first
    return memos_path(sidebar_view: "tag") if first.nil?

    memos_path(sidebar_view: "tag", tag_id: first.id)
  end

  def memos_sidebar_search_tab_path
    if (memo = memo_sidebar_open_memo)
      q = { sidebar_view: "search" }
      q[:q] = @memo_search_query if defined?(@memo_search_query) && @memo_search_query.present?
      return memo_sidebar_open_memo_path(memo, q)
    end

    if defined?(@memo_search_query) && @memo_search_query.present?
      memos_path(sidebar_view: "search", q: @memo_search_query)
    else
      memos_path(sidebar_view: "search")
    end
  end

  def memo_sidebar_view_tab_classes(mode)
    base = "flex-1 rounded-md px-2 py-1.5 text-center text-xs font-medium transition focus:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400"
    active = defined?(@sidebar_view) && @sidebar_view == mode
    if active
      "#{base} bg-white text-zinc-900 shadow-sm"
    else
      "#{base} text-zinc-600 hover:text-zinc-900"
    end
  end

  # 一覧左アイコン
  def memo_list_state_lucide_name(memo)
    memo.display_as_draft? ? "eye" : "book-open"
  end

  def memo_list_state_icon_title(memo)
    if memo.display_as_draft?
      memo.file_committed_at.present? ? "ドラフト（再編集・未コミット）" : "ドラフト（ファイル未保存）"
    else
      "ファイル保存済み"
    end
  end

  # サイドバー用: policy_scope 内のディレクトリを parent_id でグルーピング（ルート行は除外）
  def memo_directory_nav_children_index(directories)
    all = Array(directories)
    root = all.find(&:root?)
    dirs = all.reject(&:root?)
    ids = all.map(&:id).to_set
    h = Hash.new { |hh, k| hh[k] = [] }
    dirs.each do |d|
      pid = if d.parent_id.present? && ids.include?(d.parent_id)
              d.parent_id
            else
              root&.id
            end
      h[pid] << d
    end
    h.transform_values! { |a| a.sort_by(&:full_path) }
    h
  end

  def memo_directory_nav_tree_roots(directories, by_parent = nil)
    by = by_parent || memo_directory_nav_children_index(directories)
    root = Array(directories).find(&:root?)
    list = root ? (by[root.id] || []) : (by[nil] || [])
    list.sort_by(&:full_path)
  end

  # 選択中のディレクトリが node の配下にあれば details を開く
  def memo_directory_tree_details_open?(directory, selected_directory)
    return false unless selected_directory
    return true if selected_directory.id == directory.id
    return false if directory.root? || directory.full_path.blank?

    selected_directory.full_path.start_with?("#{directory.full_path}/")
  end

  # 現在選択ディレクトリが配下にあれば details を開く
  def memo_directory_nav_details_open?(directory)
    return true unless defined?(@current_memo_directory) && @current_memo_directory

    memo_directory_tree_details_open?(directory, @current_memo_directory)
  end

  def memo_directory_picker_details_open?(directory, selected_parent)
    memo_directory_tree_details_open?(directory, selected_parent)
  end

  def memo_directory_parent_picker_button_classes(selected:)
    base = "w-full min-w-0 truncate rounded-md px-2 py-1.5 text-left text-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400"
    if selected
      "#{base} bg-zinc-200 font-medium text-zinc-900"
    else
      "#{base} text-zinc-700 hover:bg-zinc-100"
    end
  end

  def memo_directory_nav_details_attrs(directory)
    attrs = { class: "memo-directory-nav-details group w-full min-w-0" }
    attrs[:open] = true if memo_directory_nav_details_open?(directory)
    attrs
  end

  # ルートからのラベルパス表示（例: /Home/kensei）。ルート自身は /。
  def memo_directory_path_from_root_label(directory)
    return "/" if directory.nil?

    directory.labeled_path_from_root
  end

  # <select> 用: DFS で [ラベル, id]。字下げは NBSP（<option> 内の通常スペースはブラウザで潰れるため）。
  # exclude_root: true のときルート行は出さず、ルート直下のフォルダから並べる（メモの保存先用）。
  # root_option_label: exclude_root が false でルート行を出すときの表示名（親ディレクトリ用）。
  def memo_directory_tree_select_option_pairs(directories, exclude_root: false, root_option_label: nil)
    dirs = Array(directories)
    root = dirs.find(&:root?)
    by_parent = memo_directory_nav_children_index(dirs)
    indent_units = "\u00a0\u00a0" # non-breaking spaces per depth level

    label_for = lambda do |node|
      if node.root?
        root_option_label.presence || node.display_name
      else
        node.display_name
      end
    end

    pairs = []
    visit = lambda do |node, depth|
      text = "#{indent_units * depth}#{label_for.call(node)}"
      pairs << [text, node.id]
      (by_parent[node.id] || []).sort_by(&:full_path).each { |ch| visit.call(ch, depth + 1) }
    end

    if exclude_root && root
      (by_parent[root.id] || []).sort_by(&:full_path).each { |ch| visit.call(ch, 0) }
    elsif root
      visit.call(root, 0)
    else
      dirs.sort_by(&:full_path).each do |d|
        pairs << [label_for.call(d), d.id]
      end
    end

    pairs
  end

  def memo_directory_nav_link_classes(directory)
    base = "block rounded-md px-2 py-1.5 text-sm transition focus:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400"
    active = defined?(@sidebar_view) && @sidebar_view == "directory" &&
      defined?(@current_memo_directory) && @current_memo_directory&.id == directory.id
    if active
      "#{base} bg-zinc-200 font-medium text-zinc-900"
    else
      "#{base} text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"
    end
  end

  def memo_tag_nav_link_classes(tag)
    base = "block rounded-md px-2 py-1.5 text-sm transition focus:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400"
    active = defined?(@sidebar_view) && @sidebar_view == "tag" &&
      defined?(@current_tag) && @current_tag&.id == tag.id
    if active
      "#{base} bg-zinc-200 font-medium text-zinc-900"
    else
      "#{base} text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900"
    end
  end

  # Wiki リンク [[full_path/slug]] の path 部分（slug のみのときは slug だけ）
  def memo_wiki_link_path(full_path, slug)
    seg = Memo.normalize_slug_fragment(slug)
    return nil if seg.blank?

    dir = full_path.to_s.strip.sub(/\A\/+/, "").sub(/\/+\z/, "")
    dir.present? ? "#{dir}/#{seg}" : seg
  end

  def memo_wiki_link_reference(full_path, slug)
    path = memo_wiki_link_path(full_path, slug)
    path ? "[[#{path}]]" : nil
  end

  def memo_wiki_link_reference_for(memo)
    seg = Memo.normalize_slug_fragment(memo.slug)
    return nil if seg.blank?

    "[[#{seg}]]"
  end

  def memo_diagram_entries(memo)
    return [] unless memo.persisted?

    MemoDiagrams.list(memo)
  end

  def memo_html(body, source_memo: nil)
    return "".html_safe if body.blank?

    processed = MemoWikiLinks.new(
      scope: policy_scope(Memo),
      source_memo: source_memo
    ).substitute(body.to_s)
    processed = MemoDiagramMacro.new(memo: source_memo).substitute(processed)

    attrs = { "icons" => "font" }
    if source_memo&.persisted?
      attrs["imagesdir"] = "#{memo_path(source_memo)}/assets/"
    end

    # safe モード: SVG は既定で <img src="...">（インライン SVG は jail で無効）。
    # image::x.svg[opts=interactive] は <object> になるため、アップロード時サニタイズに依存する。
    Asciidoctor.convert(
      processed,
      safe: :safe,
      standalone: false,
      attributes: attrs
    ).html_safe
  end

  # DB は JSON。編集フォームでは YAML で入力・表示する。
  def memo_properties_yaml_value(memo)
    h = memo.properties.presence || {}
    return "" if h.blank?

    YAML.dump(h.deep_stringify_keys).sub(/\A---\s*\n?/, "").strip
  end

  # 参照表示用（JSON のまま見せる場合）
  def memo_properties_json_value(memo)
    JSON.pretty_generate(memo.properties.presence || {})
  end

  def memo_title_input_value(memo)
    memo.title_unfilled? ? "" : memo.title
  end

  # タグ行のインライン入力（チップの右に伸びる）
  def memo_form_tag_input_inline
    [
      "min-w-[6rem] flex-1 border-0 border-b-0 bg-transparent px-0 py-0.5",
      "text-sm text-zinc-900 shadow-none placeholder:text-zinc-400",
      "focus:outline-none focus:ring-0"
    ].join(" ")
  end

  def memo_tag_names_for_datalist
    Tag.order(:name).pluck(:name)
  end

  # 編集フォーム用：下線のみのコンパクト入力
  def memo_sidebar_search_input
    [
      "block w-full min-w-0 rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-sm text-zinc-900",
      "placeholder:text-zinc-400 focus:border-zinc-900 focus:outline-none focus:ring-0"
    ].join(" ")
  end

  def memo_form_underline_input(extra_classes = "")
    [
      "block w-full border-0 border-b border-zinc-300 rounded-none bg-transparent px-0 py-1.5",
      "text-zinc-900 shadow-none placeholder:text-zinc-400",
      "focus:border-zinc-900 focus:outline-none focus:ring-0",
      extra_classes
    ].reject(&:blank?).join(" ")
  end

  def memo_form_underline_properties_textarea(memo)
    err = memo.errors[:properties_yaml].any?
    border = err ? "border-red-500 focus:border-red-600" : "border-zinc-300 focus:border-zinc-900"
    [
      "block w-full border-0 border-b #{border} rounded-none bg-transparent px-0 py-1.5 min-h-[5rem]",
      "font-mono text-sm leading-relaxed text-zinc-900 resize-y shadow-none placeholder:text-zinc-400",
      "focus:outline-none focus:ring-0"
    ].join(" ")
  end

  def memo_form_underline_body
    [
      "block w-full border-0 border-b border-zinc-300 rounded-none bg-transparent px-0 py-2 min-h-[18rem]",
      "font-mono text-sm leading-relaxed text-zinc-900 resize-y shadow-none placeholder:text-zinc-400",
      "focus:border-zinc-900 focus:outline-none focus:ring-0"
    ].join(" ")
  end

end
