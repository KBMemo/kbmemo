module MemosHelper
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

  # 一覧のメモ行: ドラフト表示中は編集、確定のみ show へ
  def memo_sidebar_memo_main_href(memo)
    memo.display_as_draft? ? edit_memo_path(memo) : memo_path(memo)
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

  def memo_html(body)
    return "".html_safe if body.blank?

    Asciidoctor.convert(
      body.to_s,
      safe: :safe,
      standalone: false
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

  # 編集フォーム用：下線のみのコンパクト入力
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
