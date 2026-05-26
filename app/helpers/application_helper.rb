module ApplicationHelper
  def memos_wide_layout?
    %w[memos memo_directories tags].include?(controller.controller_path)
  end

  # メモ一覧サイドバーなしで、ヘッダー・本文を広幅にする画面
  def wide_content_layout?
    memos_wide_layout? || controller.controller_path.in?(%w[memo_diagrams boards]) || theme_studio_layout?
  end

  def theme_studio_layout?
    controller.controller_path == "themes" && controller.action_name == "studio"
  end

  def content_max_width_class
    return "max-w-none" if theme_studio_layout?
    return "max-w-[1800px]" if wide_content_layout?

    "max-w-3xl"
  end

  def new_memo_path_with_current_directory
    opts = memo_sidebar_nav_query.dup
    unless defined?(@sidebar_view) && @sidebar_view == "tag"
      if defined?(@current_memo_directory) && @current_memo_directory && !@current_memo_directory.root?
        opts[:memo_directory_id] ||= @current_memo_directory.id
      end
    end
    return new_memo_path if opts.blank?

    new_memo_path(opts)
  end

  def kb_theme_sync_enabled?
    rodauth.rails_account.present?
  end

  def kb_account_theme_json
    return "null" unless rodauth.rails_account

    payload = rodauth.rails_account.theme_preference_payload
    {
      active_theme_id: payload["active_theme_id"],
      custom_themes: payload["custom_themes"].map do |theme|
        {
          id: theme["id"],
          label: theme["label"],
          base_theme: theme["base_theme"],
          variables: theme["variables"] || {},
          rules: theme["rules"] || []
        }
      end
    }.to_json
  end

  def kb_focus_ring
    "focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--kb-border-strong)] focus-visible:ring-offset-2"
  end

  def kb_field_input_classes
    "kb-input mt-1 block w-full rounded-md px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-1 focus:ring-[var(--kb-accent)]"
  end

  def kb_page_title
    "text-xl font-semibold kb-text-primary"
  end

  def kb_section_title
    "text-base font-semibold kb-text-primary"
  end

  def kb_label
    "block text-sm font-medium kb-text-primary"
  end

  def kb_link_table
    "font-medium kb-text-primary underline decoration-[var(--kb-border-strong)] hover:opacity-80"
  end

  def kb_link_muted
    "kb-chrome-link"
  end

  def kb_toolbar_btn
    "kb-toolbar-btn rounded-md px-2 py-1 text-xs font-medium"
  end

  def kb_table
    "kb-table w-full border-collapse text-sm"
  end

  def kb_table_head
    "border-b kb-border text-left text-xs uppercase kb-text-muted"
  end

  def kb_underline_input(extra = "")
    ["kb-underline-input block w-full px-0 py-1.5 shadow-none focus:outline-none focus:ring-0", extra].reject(&:blank?).join(" ")
  end

  def kb_auth_field_classes(error: false)
    if error
      "mt-2 text-sm w-full kb-input border-red-600 focus:border-red-600 focus:ring-red-500"
    else
      "mt-2 text-sm w-full #{kb_field_input_classes}"
    end
  end

  def kb_auth_underline_field_classes
    "mt-2 w-full kb-underline-input py-2 px-0 text-sm"
  end

  def kb_auth_submit_classes
    "kb-chrome-btn-primary w-full cursor-pointer px-4 py-2.5 #{kb_focus_ring}"
  end

  def kb_hint_popover
    "kb-hint-popover absolute z-20 w-72 rounded-md p-2 text-xs leading-relaxed"
  end

  def kb_hint_trigger
    "flex h-5 w-5 cursor-pointer list-none items-center justify-center rounded kb-text-subtle hover:bg-[var(--kb-bg-muted)] hover:text-[var(--kb-text-secondary)]"
  end

  def kb_tag_input_row
    "kb-tag-input-row flex min-h-9 flex-wrap items-center gap-2 pb-1 pt-0.5"
  end

  def kb_icon_btn(extra = "")
    ["kb-icon-btn", extra, kb_focus_ring].reject(&:blank?).join(" ")
  end

  def kb_resizer
    "kb-resizer hidden shrink-0 self-stretch w-2 cursor-col-resize md:block z-10"
  end

  def kb_sidebar_toggle_btn
    [
      "hidden md:flex fixed z-30 h-8 w-5 items-center justify-center rounded-sm bg-transparent",
      "text-base leading-none kb-text-subtle hover:bg-[color-mix(in_srgb,var(--kb-bg-muted)_90%,transparent)]",
      "hover:text-[var(--kb-text-secondary)]", kb_focus_ring
    ].join(" ")
  end

  def kb_toolbar_btn_sm
    "#{kb_toolbar_btn} px-2 py-1 text-xs font-medium"
  end

  def kb_btn_secondary_sm
    "kb-chrome-btn-secondary px-4 py-2 text-sm"
  end

  def kb_btn_primary_sm
    "kb-chrome-btn-primary px-4 py-2 text-sm"
  end
end
