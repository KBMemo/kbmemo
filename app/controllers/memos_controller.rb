class MemosController < ApplicationController
  prepend_before_action :record_memo_view_history, only: %i[show edit]
  prepend_before_action :set_memo, only: %i[show edit update destroy draft append_ai_reply commit revert_draft checklist_toggle update_directory update_tags render_diagram]
  before_action :set_memo_groups_for_form, only: %i[new create edit update]
  before_action :set_memo_templates_for_new, only: %i[new create]
  include MemoSidebar

  after_action :verify_authorized

  def wiki_completions
    authorize Memo, :wiki_completions?
    source =
      if params[:memo_id].present?
        policy_scope(Memo).find_by(id: params[:memo_id])
      end
    entries = MemoWikiCompletions.new(scope: policy_scope(Memo), source_memo: source).call(params[:q])
    render json: entries
  end

  def wiki_link_labels
    authorize Memo, :wiki_completions?
    source =
      if params[:memo_id].present?
        policy_scope(Memo).find_by(id: params[:memo_id])
      end
    targets = Array(params[:targets])
    labels = MemoWikiLinkLabels.new(scope: policy_scope(Memo), source_memo: source).call(targets)
    render json: labels
  end

  def sidebar_memo_list
    authorize Memo, :index?
    view = params[:sidebar_view].to_s

    if params[:append].present?
      return head :not_found unless %w[history search tag directory].include?(view)

      offset = [ params[:offset].to_i, 0 ].max
      load_sidebar_memos_page(offset: offset)
      return render partial: "memos/sidebar_memo_list_append", layout: false
    end

    return head :not_found unless %w[history search].include?(view)

    if view == "history" && params[:open_memo_id].present?
      @memo = policy_scope(Memo).find_by(id: params[:open_memo_id])
      # 表示中メモの履歴記録をこの同期リフレッシュで行う。Turbo の prefetch キャッシュ再利用で
      # 実クリックがサーバーに届かない場合でも、ここで move-to-top を成立させる。
      # この同期エンドポイント自体が prefetch された場合は記録しない（順序を崩さない）。
      if !turbo_prefetch_request? && record_view_for(@memo)
        load_sidebar_memos_list # 記録後の最新順で一覧を再構築する
      end
    end
    render partial: "memos/sidebar_memo_list_container", layout: false
  end

  # 左: ディレクトリツリー / 右: チェックボックス付きメモ一覧 + 一括操作
  def manage
    authorize Memo, :index?
    @notebooks = Notebook.where(account_id: rodauth.rails_account&.id).order(:title)
  end

  def bulk_add_tags
    authorize Memo, :index?
    labels = parse_tag_labels(params[:tag_list])
    return redirect_back_to_manage(alert: "追加するタグを入力してください。") if labels.empty?

    tags = labels.map { |label| Tag.resolve_label!(label) }
    count = each_authorized_memo(:update?) do |memo|
      memo.tags = (memo.tags.to_a + tags).uniq
      memo.save(validate: false)
      memo.touch
      true
    end
    redirect_back_to_manage(notice: "#{count} 件のメモにタグを追加しました。")
  end

  def bulk_remove_tags
    authorize Memo, :index?
    normalized = parse_tag_labels(params[:tag_list]).map(&:downcase)
    return redirect_back_to_manage(alert: "削除するタグを入力してください。") if normalized.empty?

    count = each_authorized_memo(:update?) do |memo|
      remaining = memo.tags.reject { |tag| normalized.include?(tag.normalized_name) }
      next false if remaining.size == memo.tags.size

      memo.tags = remaining
      memo.save(validate: false)
      memo.touch
      true
    end
    redirect_back_to_manage(notice: "#{count} 件のメモからタグを削除しました。")
  end

  def bulk_move_directory
    authorize Memo, :index?
    redirect_back_to_manage(alert: "メモのディレクトリ移動はできません。保存先は作成日で自動決まります。")
  end

  def bulk_add_to_notebook
    authorize Memo, :index?
    notebook = policy_scope(Notebook).find_by(id: params[:notebook_id])
    return redirect_back_to_manage(alert: "ノートブックを選んでください。") if notebook.nil?

    authorize notebook, :manage_memos?
    added = 0
    skipped = 0
    policy_scope(Memo).where(id: Array(params[:memo_ids])).each do |memo|
      next unless policy(memo).add_to_notebook?

      begin
        Notebooks::AddMemo.call(notebook: notebook, memo: memo)
        added += 1
      rescue Notebooks::Error
        skipped += 1
      end
    end
    notice = "#{added} 件のメモをノートブックに追加しました。"
    notice += "（#{skipped} 件は既に別のノートブックに所属のためスキップ）" if skipped.positive?
    redirect_back_to_manage(notice: notice)
  end

  def index
    authorize Memo
    if params[:q].present? && params[:sidebar_view] != "search"
      redirect_to memos_path(sidebar_view: "search", q: params[:q])
    end
  end

  def show
    authorize @memo
  end

  # メモ表示中の [source,plantuml] / [source,mermaid] / [source,svg] ブロックを
  # レンダリングして SVG を返す（図・画像 ⇄ ソースのトグル用）。保存はしない。
  def render_diagram
    authorize @memo, :show_diagram?
    engine = MemoDiagram.engine_from_lang(params[:engine])
    unless engine
      return render json: { error: "対応していない種別です（plantuml / mermaid / svg）" }, status: :unprocessable_entity
    end

    source = params[:source].to_s
    return render json: { error: "ソースが空です" }, status: :unprocessable_entity if source.strip.blank?

    normalized = MemoDiagram.normalize_source(engine, source)
    svg = MemoDiagramRenderer.render(engine: engine, source: normalized)
    render_sanitized_diagram_svg(svg)
  rescue MemoDiagram::InvalidPath, MemoDiagramRenderer::Error, MemoDiagramRenderer::Unavailable => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def new
    @memo = Memo.new(account: rodauth.rails_account)
    authorize @memo
    return if params[:template_id].blank?

    @selected_memo_template = @memo_templates.find(params[:template_id])
    rendered = MemoTemplateRenderer.new(template: @selected_memo_template).call
    @memo.assign_attributes(
      title: rendered.title,
      title_manual: rendered.title.present?,
      body: rendered.body
    )
    @initial_tag_list = rendered.tag_list
    return if params[:duplicate].to_s == "create" || rendered.title.blank?

    @existing_template_memo = policy_scope(Memo)
      .where(account_id: rodauth.rails_account.id, title: rendered.title)
      .order(updated_at: :desc, id: :desc)
      .first
  end

  def edit
    authorize @memo, :show? if @memo.sync_read_only?
    if @memo.sync_read_only?
      redirect_to @memo, alert: "このメモは docs/ から同期されています。リポジトリの AsciiDoc を更新して bin/rails kbmemo:docs:sync を実行してください。"
      return
    end
    authorize @memo
  end

  def create
    @memo = Memo.new(account: rodauth.rails_account)
    authorize @memo
    unless assign_memo_fields(@memo)
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @memo.errors.full_messages }, status: :unprocessable_entity }
      end
      return
    end

    if @memo.save
      respond_to do |format|
        format.html { redirect_to edit_memo_path(@memo), notice: "メモを作成しました。" }
        format.json do
          render json: {
            id: @memo.id,
            uid: @memo.uid,
            draft_url: draft_memo_url(@memo, memo_sidebar_nav_query),
            edit_path: edit_memo_path(@memo),
            update_url: memo_path(@memo),
            show_path: memo_path(@memo),
            form_dom_id: helpers.dom_id(@memo, :edit_form),
            title_unfilled: @memo.title_unfilled?,
            slug: @memo.slug,
            tsuzura_authorize_url: internal_tsuzura_sign_urls_path,
            tsuzura_albums_url: internal_tsuzura_albums_path,
            tsuzura_album_url_template: internal_tsuzura_album_path("__ID__")
          }, status: :created
        end
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @memo.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update
    authorize @memo
    unless assign_memo_fields(@memo)
      render_commit_failure(:edit)
      return
    end

    commit_memo!(redirect_path: memo_path(@memo))
  rescue MemoRepository::Error => e
    flash.now[:alert] = e.message
    render_commit_failure(:edit)
  end

  def commit
    authorize @memo, :commit?
    unless @memo.display_as_draft?
      respond_to do |format|
        format.html { redirect_to memo_path(@memo) }
        format.turbo_stream { render_commit_success_streams }
      end
      return
    end

    commit_memo!(redirect_path: memo_path(@memo), failure_render: nil)
  rescue MemoRepository::Error => e
    respond_to do |format|
      format.html { redirect_to memo_path(@memo), alert: e.message }
      format.turbo_stream do
        flash.now[:alert] = e.message
        render_commit_success_streams(status: :unprocessable_entity)
      end
    end
  end

  def destroy
    authorize @memo
    memo_id = @memo.id
    @memo.destroy
    load_sidebar_memos_list

    respond_to do |format|
      format.html do
        redirect_to memos_path(memo_sidebar_nav_query),
          notice: "メモを削除しました。",
          status: :see_other
      end
      format.turbo_stream do
        render turbo_stream: memo_destroy_sidebar_streams(memo_id)
      end
    end
  end

  def checklist_toggle
    authorize @memo, :update?
    checked = ActiveModel::Type::Boolean.new.cast(params[:checked])
    MemoChecklist.toggle!(@memo, id: params.require(:checklist_id), checked: checked)
    @memo.save(validate: false)
    render_show_content_turbo_stream
  rescue MemoChecklist::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update_directory
    authorize @memo, :update?
    render json: { error: "メモの保存先は作成日で自動決まります" }, status: :unprocessable_entity
  end

  def update_tags
    authorize @memo, :update?
    @memo.assign_tags_from_list(params.require(:tag_list))
    @memo.save(validate: false)
    @memo.touch
    render_show_content_turbo_stream
  end

  def draft
    authorize @memo
    display_as_draft_before = @memo.display_as_draft?
    file_committed_before = @memo.file_committed_at.present?
    repo = MemoRepository.new
    old_rel = repo.relative_path_for(@memo)
    old_abs = repo.absolute_path_for(@memo)

    wrapper = ActionController::Parameters.new(memo: draft_params)
    unless assign_memo_fields(@memo, wrapper)
      render json: { errors: @memo.errors.full_messages }, status: :unprocessable_entity
      return
    end

    @memo.apply_title_from_body_rules!
    @memo.apply_slug_from_title_rules!
    @memo.apply_storage_slug!

    new_rel = repo.relative_path_for(@memo)

    begin
      if old_abs.exist? && old_rel.to_s != new_rel.to_s
        repo.relocate_file!(from_relative: old_rel, to_relative: new_rel)
      end
    rescue MemoRepository::Error => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
      return
    end

    if @memo.save(validate: false)
      load_sidebar_memos_list
      broadcast_updated_show_content
      respond_to do |format|
        format.turbo_stream do
          streams = [
            turbo_stream.replace(
              "memo_title_field",
              partial: "memos/title_field",
              locals: { memo: @memo }
            ),
            turbo_stream.replace("memos_list_panel", partial: "memos/list_panel")
          ]
          if @memo.display_as_draft? != display_as_draft_before ||
             @memo.file_committed_at.present? != file_committed_before
            streams << turbo_stream.replace(
              "memo_form_actions",
              partial: "memos/form_actions",
              locals: { memo: @memo, memo_edit_form_id: helpers.dom_id(@memo, :edit_form) }
            )
          end
          render turbo_stream: streams
        end
        format.json do
          render json: {
            uid: @memo.uid,
            saved_at: @memo.updated_at.iso8601(3),
            title: @memo.title,
            title_manual: @memo.title_manual,
            title_unfilled: @memo.title_unfilled?,
            slug: @memo.slug,
            slug_manual: @memo.slug_manual,
            file_committed: @memo.file_committed_at.present?,
            display_as_draft: @memo.display_as_draft?
          }
        end
      end
    else
      render json: { errors: @memo.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def append_ai_reply
    authorize @memo
    reply = params[:content].to_s.strip
    if reply.blank?
      render json: { error: "追記する応答がありません。" }, status: :unprocessable_entity
      return
    end

    @memo.with_lock do
      @memo.body = [ @memo.body.to_s.rstrip.presence, reply ].compact.join("\n\n")
      MemoChecklist.sync_properties_from_body!(@memo)
      @memo.save!(validate: false)
    end

    broadcast_updated_show_content
    render json: {
      saved_at: @memo.updated_at.iso8601(3),
      display_as_draft: @memo.display_as_draft?
    }
  end

  def revert_draft
    authorize @memo, :revert_draft?

    unless @memo.file_committed_at.present?
      render json: { errors: [ "コミット済みのメモのみ復元できます" ] }, status: :unprocessable_entity
      return
    end

    repo = MemoRepository.new

    begin
      snapshot = repo.read_committed_snapshot!(@memo)
    rescue MemoRepository::Error => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
      return
    end

    @memo.body = snapshot[:body].to_s
    @memo.title = snapshot[:title].presence || Memo::TITLE_PLACEHOLDER
    @memo.slug = snapshot[:slug]
    @memo.memo_directory = snapshot[:memo_directory]
    @memo.properties = snapshot[:properties].presence || {}
    @memo.assign_tags_from_list(Array(snapshot[:tags]).join(", "))

    derived = Memo.derived_title_from_body(@memo.body)
    @memo.title_manual = !Memo.title_unfilled_value?(@memo.title) && @memo.title.to_s.strip != derived.to_s.strip
    @memo.slug_manual = true
    @memo.apply_storage_slug!

    committed_rel = snapshot[:relative_path]

    begin
      repo.write_work_tree_at!(committed_rel, snapshot[:file_content])
      repo.remove_work_tree_files_for_memo_except!(@memo, keep_relative: committed_rel)
    rescue MemoRepository::Error => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
      return
    end

    committed_at = @memo.file_committed_at
    if @memo.save(validate: false)
      @memo.update_columns(updated_at: committed_at)
      load_sidebar_memos_list
      broadcast_updated_show_content
      flash[:notice] = "最後にコミットした内容を読み込みました。"
      render json: { edit_path: edit_memo_path(@memo) }
    else
      render json: { errors: @memo.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def render_sanitized_diagram_svg(svg)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Kbmemo-Svg-Sanitized"] = "MemoSvgSanitizer"
    response.headers["Cache-Control"] = "no-store"
    render json: { svg: svg, sanitized: true }
  end

  # Turbo の broadcast が ApplicationController.render 経由だと rodauth が無く memo_html が失敗するので、同一リクエストで HTML を組み立ててから送る。
  def commit_memo!(redirect_path:, failure_render: :edit)
    @memo.apply_title_from_body_rules!
    @memo.apply_slug_from_title_rules!

    unless @memo.valid?
      respond_to do |format|
        format.html do
          if failure_render
            render failure_render, status: :unprocessable_entity
          else
            redirect_to edit_memo_path(@memo), alert: @memo.errors.full_messages.join(" ")
          end
        end
        format.turbo_stream do
          flash.now[:alert] = @memo.errors.full_messages.join(" ")
          render_commit_failure_stream(failure_render || :edit)
        end
      end
      return
    end

    write_memo_to_git!
    @memo.save!
    @memo.update_column(:file_committed_at, @memo.updated_at)
    broadcast_updated_show_content
    respond_to do |format|
      format.html { redirect_to redirect_path, notice: "ファイルへ保存し、Git に記録しました。" }
      format.turbo_stream do
        flash.now[:notice] = "ファイルへ保存し、Git に記録しました。"
        load_sidebar_memos_list
        render_commit_success_streams
      end
    end
  end

  def render_commit_success_streams(status: :ok)
    load_sidebar_memos_list unless defined?(@memos)
    render turbo_stream: [
      turbo_stream.replace(
        "memos_editor_scroll",
        partial: "memos/show_editor",
        locals: { memo: @memo }
      ),
      turbo_stream.replace("memos_list_panel", partial: "memos/list_panel"),
      turbo_stream.replace("flash-live", partial: "shared/flash_toasts"),
      turbo_stream.update(
        "memo_ai_sidebar_panel",
        partial: "memos/ai_panel",
        locals: { memo: @memo, editing: false }
      )
    ], status: status
  end

  def render_commit_failure(view)
    respond_to do |format|
      format.html { render view, status: :unprocessable_entity }
      format.turbo_stream { render_commit_failure_stream(view) }
    end
  end

  def render_commit_failure_stream(_view)
    render turbo_stream: [
      turbo_stream.replace(
        "memos_editor_scroll",
        partial: "memos/edit_editor",
        locals: { memo: @memo }
      ),
      turbo_stream.replace("flash-live", partial: "shared/flash_toasts")
    ], status: :unprocessable_entity
  end

  def write_memo_to_git!
    repo = MemoRepository.new
    old_rel = repo.relative_path_for(@memo)
    old_abs = repo.absolute_path_for(@memo)
    old_assets_rel = repo.assets_dir_relative_for(@memo)
    new_rel = repo.relative_path_for(@memo)
    new_assets_rel = repo.assets_dir_relative_for(@memo)

    if old_abs.exist? && old_rel.to_s != new_rel.to_s
      repo.relocate_path!(from_relative: old_rel, to_relative: new_rel)
    end
    if old_assets_rel.to_s != new_assets_rel.to_s && repo.root.join(old_assets_rel).directory?
      repo.relocate_path!(from_relative: old_assets_rel, to_relative: new_assets_rel)
    end
    repo.write_and_commit!(@memo)
  end

  def broadcast_updated_show_content
    html = render_to_string(partial: "memos/show_content", locals: { memo: @memo }, formats: [ :html ])
    @memo.broadcast_replace(html: html)
  end

  def render_show_content_turbo_stream
    html = render_to_string(partial: "memos/show_content", locals: { memo: @memo }, formats: [ :html ])
    render turbo_stream: turbo_stream.replace(helpers.dom_id(@memo), html: html)
  end

  def parse_tag_labels(raw)
    raw.to_s.split(/[,，]/).map(&:strip).reject(&:blank?).uniq
  end

  # 選択メモのうち permission を満たすものに対して block を実行し、変更があった件数を返す。
  def each_authorized_memo(permission)
    count = 0
    policy_scope(Memo).where(id: Array(params[:memo_ids])).each do |memo|
      next unless policy(memo).public_send(permission)

      count += 1 if yield(memo)
    end
    count
  end

  def redirect_back_to_manage(**flash_opts)
    redirect_to manage_memos_path(memo_directory_id: params[:memo_directory_id].presence), **flash_opts
  end

  # show は set_memo・authorize のあと未ログインでも全体公開のみ閲覧可。それ以外の action は通常どおり require_account。
  def require_authentication
    return if action_name == "show"

    super
  end

  def record_memo_view_history
    return if sidebar_sync_request?
    return if turbo_prefetch_request?

    record_view_for(@memo)
  end

  # メモの表示履歴を記録する（記録できたら true）。
  def record_view_for(memo)
    account = rodauth.rails_account
    return false unless account && memo&.persisted?
    return false unless policy(memo).show?

    MemoViewHistory.record!(account: account, memo: memo)
    true
  end

  def sidebar_sync_request?
    request.headers["X-Kbmemo-Sidebar-Sync"].present?
  end

  def turbo_prefetch_request?
    purpose = request.headers["X-Sec-Purpose"].to_s
    purpose.casecmp("prefetch").zero? || request.headers["Sec-Purpose"].to_s.casecmp("prefetch").zero?
  end

  def set_memo_groups_for_form
    @memo_groups_for_form = MemoGroup.for_account(rodauth.rails_account.id).order(:name)
  end

  def set_memo_templates_for_new
    @memo_templates = policy_scope(MemoTemplate).order(:name)
  end

  def set_memo
    base = policy_scope(Memo).includes(:tags, :memo_directory, :account, :memo_group, :board)
    key = params[:id].to_s
    @memo = find_memo_in_scope(base, key)
  rescue ActiveRecord::RecordNotFound
    redirect_guest_to_login_for_existing_memo!(key)
    raise
  end

  def find_memo_in_scope(scope, key)
    if key.upcase.match?(Memo::UID_FORMAT)
      scope.find_by!(uid: key.upcase)
    else
      scope.find(key)
    end
  end

  # 未ログインで policy_scope 外のメモ URL を開いたとき、存在するなら 404 ではなくログインへ。
  # ログイン後は Rodauth の login_return_to_requested_location? で元 URL に戻る。
  def redirect_guest_to_login_for_existing_memo!(key)
    return unless action_name == "show"
    return if rodauth.rails_account.present?
    return unless memo_exists_unscoped?(key)

    rodauth.require_account
  end

  def memo_exists_unscoped?(key)
    if key.upcase.match?(Memo::UID_FORMAT)
      Memo.exists?(uid: key.upcase)
    else
      Memo.exists?(id: key)
    end
  end

  def memo_params
    params.require(:memo).permit(
      :title, :body, :title_manual, :properties_yaml,
      :visibility, :memo_group_id
    )
  end

  def draft_params
    params.require(:memo).permit(:body, :title, :title_manual, :tag_list, :properties_yaml)
  end

  # raw_params は通常の request.params か、draft 用に構築した Parameters（キー :memo）
  def assign_memo_fields(memo, raw_params = nil)
    raw_params ||= params
    src = raw_params.require(:memo).permit(
      :title, :body, :title_manual, :tag_list, :properties_yaml,
      :visibility, :memo_group_id
    )
    memo.assign_attributes(
      src.slice(:title, :body, :title_manual, :visibility, :memo_group_id)
    )
    memo.assign_tags_from_list(src[:tag_list]) if src.key?(:tag_list)

    if src.key?(:properties_yaml)
      memo.properties = parse_properties_yaml(src[:properties_yaml])
    end

    if src.key?(:body)
      MemoChecklist.sync_properties_from_body!(memo)
    end

    true
  rescue Psych::SyntaxError
    memo.errors.add(:properties_yaml, "must be valid YAML")
    false
  rescue ArgumentError => e
    memo.errors.add(:properties_yaml, e.message)
    false
  end

  def parse_properties_yaml(raw)
    return {} if raw.blank?

    parsed = YAML.safe_load(
      raw.to_s,
      permitted_classes: [ Symbol, Date, Time ],
      permitted_symbols: [],
      aliases: true
    )

    return {} if parsed.nil?

    raise ArgumentError, "properties must be a YAML mapping (object)" unless parsed.is_a?(Hash)

    parsed.deep_stringify_keys
  end

  def memo_destroy_sidebar_streams(memo_id)
    [
      turbo_stream.remove("sidebar_row_memo_#{memo_id}"),
      turbo_stream.replace("memos_list_panel", partial: "memos/list_panel"),
      turbo_stream.replace("memos_editor_scroll", partial: "memos/editor_placeholder")
    ]
  end
end
