class MemosController < ApplicationController
  prepend_before_action :set_memo, only: %i[show edit update destroy draft]
  include MemoSidebar

  def index
  end

  def show
  end

  def new
    @memo = Memo.new(memo_directory_id: memo_directory_id_for_new)
  end

  def edit
  end

  def create
    @memo = Memo.new(memo_directory_id: memo_directory_id_for_new)
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
            draft_url: draft_memo_url(@memo),
            edit_path: edit_memo_path(@memo),
            title_unfilled: @memo.title_unfilled?,
            slug: @memo.slug
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
    repo = MemoRepository.new
    old_rel = repo.relative_path_for(@memo)
    old_abs = repo.absolute_path_for(@memo)

    unless assign_memo_fields(@memo)
      render :edit, status: :unprocessable_entity
      return
    end

    @memo.apply_title_from_body_rules!
    @memo.apply_slug_from_title_rules!

    unless @memo.valid?
      render :edit, status: :unprocessable_entity
      return
    end

    new_rel = repo.relative_path_for(@memo)

    begin
      if old_abs.exist? && old_rel.to_s != new_rel.to_s
        repo.relocate_file!(from_relative: old_rel, to_relative: new_rel)
      end
      repo.write_and_commit!(@memo)
    rescue MemoRepository::Error => e
      flash.now[:alert] = e.message
      render :edit, status: :unprocessable_entity
      return
    end

    if @memo.save
      @memo.update_column(:file_committed_at, @memo.updated_at)
      @memo.broadcast_replace partial: "memos/show_content"
      redirect_to memo_path(@memo), notice: "ファイルへ保存し、Git に記録しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    dir_id = @memo.memo_directory_id
    @memo.destroy
    redirect_to memos_url(memo_directory_id: dir_id), notice: "メモを削除しました。", status: :see_other
  end

  def draft
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
      @memo.broadcast_replace partial: "memos/show_content"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "memo_title_field",
              partial: "memos/title_field",
              locals: { memo: @memo }
            ),
            turbo_stream.replace(
              "memo_slug_field",
              partial: "memos/slug_field",
              locals: { memo: @memo }
            ),
            turbo_stream.replace(
              "memo_directory_field",
              partial: "memos/directory_field",
              locals: { memo: @memo }
            ),
            turbo_stream.replace("memos_list_panel", partial: "memos/list_panel")
          ]
        end
        format.json do
          render json: {
            saved_at: @memo.updated_at.iso8601(3),
            title: @memo.title,
            title_manual: @memo.title_manual,
            title_unfilled: @memo.title_unfilled?,
            slug: @memo.slug,
            slug_manual: @memo.slug_manual,
            file_committed: @memo.file_committed_at.present?
          }
        end
      end
    else
      render json: { errors: @memo.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def memo_directory_id_for_new
    if params[:memo_directory_id].present?
      MemoDirectory.find_by(id: params[:memo_directory_id])&.id
    else
      MemoDirectory.root.id
    end
  end

  def set_memo
    @memo = Memo.includes(:tags, :memo_directory).find(params[:id])
  end

  def memo_params
    params.require(:memo).permit(:title, :body, :slug, :title_manual, :slug_manual, :properties_yaml, :memo_directory_id)
  end

  def draft_params
    params.require(:memo).permit(:body, :title, :title_manual, :slug, :slug_manual, :tag_list, :properties_yaml, :memo_directory_id)
  end

  # raw_params は通常の request.params か、draft 用に構築した Parameters（キー :memo）
  def assign_memo_fields(memo, raw_params = nil)
    raw_params ||= params
    src = raw_params.require(:memo).permit(:title, :body, :slug, :title_manual, :slug_manual, :tag_list, :properties_yaml, :memo_directory_id)
    memo.assign_attributes(src.slice(:title, :body, :slug, :title_manual, :slug_manual, :memo_directory_id))
    memo.assign_tags_from_list(src[:tag_list]) if src.key?(:tag_list)

    if src.key?(:properties_yaml)
      memo.properties = parse_properties_yaml(src[:properties_yaml])
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
      permitted_classes: [Symbol, Date, Time],
      permitted_symbols: [],
      aliases: true
    )

    return {} if parsed.nil?

    raise ArgumentError, "properties must be a YAML mapping (object)" unless parsed.is_a?(Hash)

    parsed.deep_stringify_keys
  end
end
