module ApplicationHelper
  INITIAL_THEME_IDS = AccountThemePreference::BUILTIN_THEME_IDS.freeze
  DARK_COLOR_SCHEME_IDS = %w[dark].freeze

  def memos_wide_layout?
    return false if memos_manage_screen?

    %w[memos memo_directories tags].include?(controller.controller_path)
  end

  # ディレクトリ・メモ一括管理画面（左ツリー／右一覧の独自 2 ペイン）
  def memos_manage_screen?
    controller.controller_path == "memos" && controller.action_name == "manage"
  end

  def notebook_show_wide_layout?
    (controller.controller_path == "notebooks" && controller.action_name == "show") ||
      (controller.controller_path == "help" && controller.action_name == "show")
  end

  def help_show?
    controller.controller_path == "help" && controller.action_name == "show"
  end

  # メモ一覧サイドバーなしで、ヘッダー・本文を広幅にする画面
  def wide_content_layout?
    memos_wide_layout? || memos_manage_screen? || notebook_show_wide_layout? ||
      controller.controller_path.in?(%w[dashboard memo_diagrams boards]) || theme_studio_layout?
  end

  def theme_studio_layout?
    controller.controller_path == "themes" && controller.action_name == "studio"
  end

  def content_max_width_class
    return "max-w-none" if theme_studio_layout?
    return "kb-content-wide" if wide_content_layout?

    "max-w-3xl"
  end

  def nav_boards_trigger_class
    classes = [ "kb-header-menu-trigger", "inline-flex", "items-center", "gap-0.5" ]
    classes << "font-semibold" if controller_path == "boards"
    classes.join(" ")
  end

  def nav_board_menu_item_class(board)
    classes = [ "kb-menu-item", "block", "truncate", "px-3", "py-2", "max-w-xs" ]
    if controller_path == "boards" && action_name == "show" && defined?(@board) && @board&.id == board.id
      classes << "font-semibold"
      classes << "kb-text-primary"
    end
    classes.join(" ")
  end

  def nav_notebooks_trigger_class
    classes = [ "kb-header-menu-trigger", "inline-flex", "items-center", "gap-0.5" ]
    classes << "font-semibold" if controller_path == "notebooks"
    classes.join(" ")
  end

  def nav_notebook_menu_item_class(notebook)
    classes = [ "kb-menu-item", "block", "truncate", "px-3", "py-2", "max-w-xs" ]
    if controller_path == "notebooks" && action_name == "show" && defined?(@notebook) && @notebook&.id == notebook.id
      classes << "font-semibold"
      classes << "kb-text-primary"
    end
    classes.join(" ")
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

  def kb_initial_theme_id
    return "default" unless rodauth.rails_account

    rodauth.rails_account.theme_active_id
  end

  def kb_initial_theme_base
    active_id = kb_initial_theme_id
    return active_id if INITIAL_THEME_IDS.include?(active_id)

    custom_theme = kb_initial_theme_payload["custom_themes"].find { |theme| theme["id"] == active_id }
    custom_theme&.fetch("base_theme", nil).presence || "default"
  end

  def kb_initial_skin_id
    return AccountThemePreference::DEFAULT_SKIN_ID unless rodauth.rails_account

    rodauth.rails_account.theme_active_skin_id
  end

  def kb_initial_color_scheme
    DARK_COLOR_SCHEME_IDS.include?(kb_initial_theme_base) || kb_initial_skin_id == "dark" ? "dark" : "light"
  end

  def tsuzura_manage_url
    Tsuzura::Endpoints.web_manage_url
  end

  def tsuzura_manage_link_label
    host = URI.parse(tsuzura_manage_url).host
    port = URI.parse(tsuzura_manage_url).port
    return host if port.blank? || [ 80, 443 ].include?(port)

    "#{host}:#{port}"
  rescue URI::InvalidURIError
    tsuzura_manage_url
  end

  def kb_account_theme_json
    return "null" unless rodauth.rails_account

    payload = kb_initial_theme_payload
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
      end,
      active_skin_id: payload["active_skin_id"],
      custom_skins: payload["custom_skins"].map do |skin|
        {
          id: skin["id"],
          label: skin["label"],
          css: skin["css"] || ""
        }
      end
    }.to_json
  end

  def kb_initial_theme_payload
    @kb_initial_theme_payload ||= rodauth.rails_account&.theme_preference_payload ||
                                  Account.normalize_theme_preference({})
  end

  def kb_focus_ring
    "kb-focus-ring"
  end

  def kb_field_input_classes
    "kb-input kb-field-input"
  end

  def kb_page_title
    "kb-page-title"
  end

  def kb_section_title
    "kb-section-title"
  end

  def kb_label
    "kb-label"
  end

  def kb_link_table
    "kb-link-table"
  end

  def kb_link_muted
    "kb-chrome-link"
  end

  def kb_toolbar_btn
    "kb-toolbar-btn"
  end

  def kb_table
    "kb-table"
  end

  def kb_table_head
    "kb-table-head"
  end

  def kb_underline_input(extra = "")
    [ "kb-underline-input", extra ].reject(&:blank?).join(" ")
  end

  def kb_auth_field_classes(error: false)
    if error
      "mt-2 text-sm w-full kb-input kb-field-error"
    else
      "mt-2 text-sm w-full #{kb_field_input_classes}"
    end
  end

  def kb_field_error_id(record, attribute)
    "#{record.model_name.param_key}_#{attribute}_error"
  end

  def kb_field_error_message(record, attribute)
    record.errors[attribute].first
  end

  def kb_field_error?(record, attribute)
    record.errors[attribute].any?
  end

  def kb_field_error_aria(record, attribute, describedby: nil)
    return nil unless kb_field_error?(record, attribute)

    ids = Array(describedby).compact_blank
    ids << kb_field_error_id(record, attribute)
    { invalid: true, describedby: ids.join(" ") }
  end

  def kb_auth_underline_field_classes
    "mt-2 w-full kb-underline-input py-2 px-0 text-sm"
  end

  def kb_auth_submit_classes
    "kb-chrome-btn-primary kb-auth-submit #{kb_focus_ring}"
  end

  def kb_hint_popover
    "kb-hint-popover"
  end

  def kb_hint_trigger
    "kb-hint-trigger"
  end

  def kb_tag_input_row
    "kb-tag-input-row"
  end

  def kb_icon_btn(extra = "")
    [ "kb-icon-btn", extra, kb_focus_ring ].reject(&:blank?).join(" ")
  end

  def kb_resizer
    "kb-resizer"
  end

  def kb_sidebar_toggle_btn
    [ "kb-sidebar-toggle-btn", kb_focus_ring ].join(" ")
  end

  def kb_toolbar_btn_sm
    kb_toolbar_btn
  end

  def kb_btn_secondary_sm
    "kb-chrome-btn-secondary kb-btn-sm"
  end

  def kb_btn_primary_sm
    "kb-chrome-btn-primary kb-btn-sm"
  end

  # Header KB monogram (public/kbmemo-brand.svg). Inline so fill=currentColor follows theme.
  def kbmemo_brand_icon
    path = Rails.root.join("public/kbmemo-brand.svg")
    svg = File.read(path)
    svg = svg.sub("<svg ", '<svg class="kb-chrome-brand-icon" width="28" height="28" ')
    raw svg
  end
end
