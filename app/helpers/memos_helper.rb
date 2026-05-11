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

  def memo_html(body)
    return "".html_safe if body.blank?

    Asciidoctor.convert(
      body.to_s,
      safe: :safe,
      standalone: false
    ).html_safe
  end

  def memo_properties_json_value(memo)
    JSON.pretty_generate(memo.properties.presence || {})
  end

  def memo_title_input_value(memo)
    memo.title_unfilled? ? "" : memo.title
  end
end
