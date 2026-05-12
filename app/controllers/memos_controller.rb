class MemosController < ApplicationController
  before_action :set_memo, only: %i[show edit update destroy draft]
  before_action :load_sidebar_memos

  def index
  end

  def show
  end

  def new
    @memo = Memo.new
  end

  def edit
  end

  def create
    @memo = Memo.new
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

    begin
      MemoRepository.new.write_and_commit!(@memo)
    rescue MemoRepository::Error => e
      flash.now[:alert] = e.message
      render :edit, status: :unprocessable_entity
      return
    end

    if @memo.save
      # 最終コミット時点と updated_at を一致させ、直後に再編集ドラフトと誤判定しないようにする
      @memo.update_column(:file_committed_at, @memo.updated_at)
      @memo.broadcast_replace partial: "memos/show_content"
      redirect_to memo_path(@memo), notice: "ファイルへ保存し、Git に記録しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @memo.destroy
    redirect_to memos_url, notice: "メモを削除しました。", status: :see_other
  end

  def draft
    wrapper = ActionController::Parameters.new(memo: draft_params)
    unless assign_memo_fields(@memo, wrapper)
      render json: { errors: @memo.errors.full_messages }, status: :unprocessable_entity
      return
    end

    @memo.apply_title_from_body_rules!
    @memo.apply_slug_from_title_rules!

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

  def load_sidebar_memos
    @memos = Memo.order(updated_at: :desc).includes(:tags)
  end

  def set_memo
    @memo = Memo.includes(:tags).find(params[:id])
  end

  def memo_params
    params.require(:memo).permit(:title, :body, :slug, :title_manual, :slug_manual, :properties_yaml)
  end

  def draft_params
    params.require(:memo).permit(:body, :title, :title_manual, :slug, :slug_manual, :tag_list, :properties_yaml)
  end

  # raw_params は通常の request.params か、draft 用に構築した Parameters（キー :memo）
  def assign_memo_fields(memo, raw_params = nil)
    raw_params ||= params
    src = raw_params.require(:memo).permit(:title, :body, :slug, :title_manual, :slug_manual, :tag_list, :properties_yaml)
    memo.assign_attributes(src.slice(:title, :body, :slug, :title_manual, :slug_manual))
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
