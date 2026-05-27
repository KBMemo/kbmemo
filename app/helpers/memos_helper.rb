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

  def memo_directory_picker_admin?
    rodauth.rails_account&.admin?
  end

  def memo_directory_picker_selectable?(directory)
    directory.directory_picker_selectable?(admin: memo_directory_picker_admin?)
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
    base = "kb-sidebar-link block border-l-2 px-3 py-3 text-sm transition #{kb_focus_ring}"
    active = memo_sidebar_selected?(key) ? "is-active" : ""
    [base, active].join(" ")
  end

  # メモ一覧の行（グリップ＋リンク）用。左ボーダーで選択中を示す。
  def memo_sidebar_memo_list_row_classes(memo_id)
    base = "kb-sidebar-row flex min-w-0 flex-1 items-stretch border-l-2 text-sm transition"
    active = memo_sidebar_selected?(memo_id) ? "is-active" : ""
    [base, active].join(" ")
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
    elsif defined?(@sidebar_view) && @sidebar_view == "history"
      h[:sidebar_view] = "history"
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
      if defined?(@current_memo_directory) && @current_memo_directory && !@current_memo_directory.root?
        q[:memo_directory_id] = @current_memo_directory.id
      end
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

  def memos_sidebar_history_tab_path
    if (memo = memo_sidebar_open_memo)
      return memo_sidebar_open_memo_path(memo, sidebar_view: "history")
    end

    memos_path(sidebar_view: "history")
  end

  def memo_sidebar_view_tab_classes(mode)
    base = "kb-sidebar-tab min-w-0 flex-1 rounded-md px-1.5 py-1.5 text-center text-[11px] font-medium transition #{kb_focus_ring}"
    active = defined?(@sidebar_view) && @sidebar_view == mode
    [base, active ? "is-active" : nil].compact.join(" ")
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
    if defined?(@nav_open_directory_ids) && @nav_open_directory_ids.include?(directory.id)
      return true
    end
    return true unless defined?(@current_memo_directory) && @current_memo_directory

    memo_directory_tree_details_open?(directory, @current_memo_directory)
  end

  def memo_directory_picker_details_open?(directory, selected_parent)
    memo_directory_tree_details_open?(directory, selected_parent)
  end

  def memo_directory_parent_picker_button_classes(selected:)
    base = "w-full min-w-0 truncate rounded-md px-2 py-1.5 text-left text-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--kb-border-strong)]"
    if selected
      "#{base} bg-[var(--kb-bg-muted)] font-medium kb-text-primary"
    else
      "#{base} kb-text-secondary hover:bg-[var(--kb-bg-muted)]"
    end
  end

  def memo_directory_nav_details_attrs(directory)
    attrs = {
      class: "memo-directory-nav-details group w-full min-w-0",
      data: { memo_directory_id: directory.id }
    }
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
    base = "kb-sidebar-nav block rounded-md px-2 py-1.5 text-sm transition #{kb_focus_ring}"
    active = defined?(@sidebar_view) && @sidebar_view == "directory" &&
      defined?(@current_memo_directory) && @current_memo_directory&.id == directory.id
    [base, active ? "is-active" : nil].compact.join(" ")
  end

  def memo_tag_nav_link_classes(tag)
    base = "kb-sidebar-nav block rounded-md px-2 py-1.5 text-sm transition #{kb_focus_ring}"
    active = defined?(@sidebar_view) && @sidebar_view == "tag" &&
      defined?(@current_tag) && @current_tag&.id == tag.id
    [base, active ? "is-active" : nil].compact.join(" ")
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

  def memo_attachment_entries(memo, body: nil)
    return [] unless memo.persisted?

    MemoAttachments.list(memo, body: body.presence || memo.body.to_s)
  end

  def memo_backlink_memos(memo)
    return [] unless memo.persisted?

    MemoWikiBacklinks.new(target_memo: memo, scope: policy_scope(Memo)).call
  end

  def memo_html(body, source_memo: nil)
    return "".html_safe if body.blank?

    text = body.to_s
    text = MemoBodyReferences.normalize_image_macro_paths(text) if source_memo&.persisted?
    text = MemoAdocIncludes.new(memo: source_memo).expand(text) if source_memo&.docs_sync_managed?

    processed = MemoWikiLinks.new(
      scope: policy_scope(Memo),
      source_memo: source_memo
    ).substitute(text)
    processed = MemoDiagramMacro.new(memo: source_memo).substitute(processed)

    attrs = {
      "icons" => "font",
      "stem" => "latexmath"
    }
    if source_memo&.persisted?
      attrs["imagesdir"] = "#{memo_path(source_memo)}/assets/"
    end

    # safe モード: SVG は既定で <img src="...">（インライン SVG は jail で無効）。
    # image::x.svg[opts=interactive] は <object> になるため、アップロード時サニタイズに依存する。
    html = Asciidoctor.convert(
      processed,
      safe: :safe,
      standalone: false,
      attributes: attrs
    )
    html = memo_html_lazy_load_images(html)
    html = memo_html_add_asset_viewer_links(html, source_memo)
    memo_html_add_checklist_controls(html, source_memo)
  end

  # 表示画面: ビューポート外の画像読み込みを遅延（<object> 図は対象外）
  def memo_html_lazy_load_images(html)
    fragment = Nokogiri::HTML.fragment(html.to_s)
    fragment.css("img:not([loading])").each do |img|
      img["loading"] = "lazy"
      img["decoding"] = "async"
    end
    fragment.to_html.html_safe
  end

  # 表示画面: [%interactive] チェックリストに id 付きトグル（properties と同期）
  def memo_html_add_checklist_controls(html, memo)
    return html if memo.blank? || !memo.persisted?

    rows = Array(memo.properties["checkboxes"])
    return html if rows.empty?

    items = MemoChecklist.interactive_items(memo)
    return html if items.empty?

    fragment = Nokogiri::HTML.fragment(html.to_s)
    inputs = fragment.css("div.checklist input[type=checkbox]")
    return html.to_s.html_safe if inputs.size != rows.size

    inputs.each_with_index do |input, index|
      row = rows[index]
      next unless row

      input["data-memo-checklist-id"] = row["id"]
      input["data-action"] = "change->memo-checklist#toggle"
      if row["checked"]
        input["checked"] = "checked"
        input["data-item-complete"] = "1"
      else
        input.remove_attribute("checked")
        input["data-item-complete"] = "0"
      end
    end
    fragment.to_html.html_safe
  end

  # 表示画面: 画像・ダイアグラムにビューア／ソースへのリンクを付与
  def memo_html_add_asset_viewer_links(html, memo)
    return html if memo.blank? || !memo.persisted?

    fragment = Nokogiri::HTML.fragment(html.to_s)
    fragment.css(".imageblock").each do |block|
      links = memo_show_asset_action_links(block, memo)
      next if links.empty?

      block.add_child(build_memo_show_asset_actions_node(fragment, links))
    end
    fragment.to_html.html_safe
  end

  # DB は JSON。編集フォームでは YAML で入力・表示する。
  def memo_properties_yaml_value(memo)
    h = memo.properties.presence || {}
    return "" if h.blank?

    YAML.dump(h.deep_stringify_keys).sub(/\A---\s*\n?/, "").strip
  end

  # 表示画面: プロパティ見出し横の 1 行要約（全文はトグルで展開）
  def memo_properties_summary_line(memo)
    props = memo.properties.presence || {}
    return "" if props.blank?

    boxes = Array(props["checkboxes"])
    if boxes.any?
      parts = boxes.map do |row|
        mark = row["checked"] ? "✓" : "○"
        label = row["label"].to_s.truncate(24)
        "#{row["id"]}: #{label} #{mark}"
      end
      line = "checkboxes: #{boxes.size}件 — #{parts.join(", ")}"
      other_keys = props.except("checkboxes")
      if other_keys.present?
        rest = memo_properties_yaml_value(memo).gsub(/\s+/, " ").strip
        line = "#{line} · #{rest}"
      end
      return truncate(line, length: 160)
    end

    truncate(memo_properties_yaml_value(memo).gsub(/\s+/, " ").strip, length: 160)
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
      "kb-field-inline min-w-[6rem] flex-1 border-0 border-b-0 bg-transparent px-0 py-0.5",
      "text-sm shadow-none focus:outline-none focus:ring-0"
    ].join(" ")
  end

  def memo_tag_names_for_datalist
    Tag.order(:name).pluck(:name)
  end

  def memo_tag_catalog_for_pills
    Tag.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
  end

  def memo_show_metadata_stimulus_data(memo)
    return {} unless policy(memo).update?

    {
      controller: "memo-show-metadata",
      memo_show_metadata_directory_url_value: update_directory_memo_path(memo),
      memo_show_metadata_tags_url_value: update_tags_memo_path(memo),
      memo_show_metadata_tag_catalog_value: memo_tag_catalog_for_pills.to_json,
      memo_show_metadata_memo_id_value: memo.id
    }
  end

  def memo_show_content_tag_options(memo)
    { id: dom_id(memo) }.tap do |opts|
      data = memo_show_metadata_stimulus_data(memo)
      opts[:data] = data if data.present?
    end
  end

  # 編集フォーム用：下線のみのコンパクト入力
  def memo_sidebar_search_input
    "kb-input block w-full min-w-0 rounded-md px-2 py-1.5 text-sm focus:outline-none focus:ring-0 focus:border-[var(--kb-accent)]"
  end

  MEMO_ASSET_URL_PATH = %r{\A/memos/(\d+)/assets/(.+)\z}

  def memo_show_asset_action_links(imageblock, memo)
    obj = imageblock.at_css("object[data]")
    if obj
      relative = memo_asset_relative_from_url(obj["data"], memo: memo)
      return [] unless relative

      return memo_show_diagram_action_links(memo, relative) if memo_diagram_svg_relative?(relative)

      return viewer_link_for_asset(memo, relative)
    end

    img = imageblock.at_css("img[src]")
    return [] unless img

    relative = memo_asset_relative_from_url(img["src"], memo: memo)
    return [] unless relative

    viewer_link_for_asset(memo, relative)
  end

  def memo_show_diagram_action_links(memo, svg_relative)
    key = memo_diagram_key_from_svg_relative(memo, svg_relative)
    source_rel = MemoDiagram.source_relative_path(key)
    links = [
      { label: "ソース", href: source_memo_diagram_path(memo, key) }
    ]
    if memo_diagram_svg_exists?(memo, svg_relative)
      links << { label: "ビューアで開く", href: view_memo_diagram_path(memo, key) }
    end
    links
  rescue MemoDiagram::InvalidPath
    []
  end

  def viewer_link_for_asset(memo, relative)
    return [] unless memo_viewable_image_relative?(relative)
    return [] unless memo_asset_exists?(memo, relative)

    [ { label: "ビューアで開く", href: asset_view_memo_path(memo, relative) } ]
  end

  def build_memo_show_asset_actions_node(fragment, links)
    doc = fragment.document
    div = Nokogiri::XML::Node.new("div", doc)
    div["class"] = "memo-show-asset-actions"
    links.each do |spec|
      a = Nokogiri::XML::Node.new("a", doc)
      a["href"] = spec[:href]
      a["class"] = "memo-show-asset-action"
      a["target"] = "_blank"
      a["rel"] = "noopener noreferrer"
      a.content = spec[:label]
      div.add_child(a)
    end
    div
  end

  def memo_asset_relative_from_url(url, memo:)
    path = url.to_s
    path = URI.parse(path).path if path.include?("://")
    match = path.match(MEMO_ASSET_URL_PATH)
    return nil unless match && match[1].to_i == memo.id

    match[2].split("/").map { |seg| CGI.unescape(seg) }.join("/")
  end

  def memo_diagram_svg_relative?(relative)
    relative.start_with?("diagrams/") && relative.downcase.end_with?(".svg")
  end

  def memo_diagram_key_from_svg_relative(memo, svg_relative)
    base = File.basename(svg_relative, ".svg")
    MemoDiagram::ALLOWED_EXTENSIONS.each do |ext|
      key = "#{base}#{ext}"
      return key if memo_asset_exists?(memo, "diagrams/#{key}")
    end
    "#{base}.mmd"
  end

  def memo_diagram_svg_exists?(memo, svg_relative)
    memo_asset_exists?(memo, svg_relative)
  end

  def memo_asset_exists?(memo, relative)
    MemoAssets.resolve_path!(memo, relative).file?
  rescue MemoAssets::InvalidFile
    false
  end

  def memo_viewable_image_relative?(relative)
    relative.match?(/\.(png|jpe?g|gif|webp|svg)\z/i)
  end

  def memo_form_underline_input(extra_classes = "")
    kb_underline_input(extra_classes)
  end

  def memo_form_underline_properties_textarea(memo)
    err = memo.errors[:properties_yaml].any?
    border = err ? "border-red-500 focus:border-red-600" : "border-[var(--kb-border-strong)] focus:border-[var(--kb-accent)]"
    [
      "kb-underline-input block w-full px-0 py-1.5 min-h-[5rem] border-0 border-b #{border}",
      "font-mono text-sm leading-relaxed resize-y shadow-none focus:outline-none focus:ring-0"
    ].join(" ")
  end

  def memo_form_underline_body
    [
      "kb-underline-input block w-full px-0 py-2 min-h-[18rem]",
      "font-mono text-sm leading-relaxed resize-y shadow-none focus:outline-none focus:ring-0"
    ].join(" ")
  end

end
