# frozen_string_literal: true

class NotebooksController < ApplicationController
  after_action :verify_authorized

  before_action :set_notebook, only: %i[show edit update destroy publish unpublish available_memos]

  def index
    authorize Notebook
    @notebooks = policy_scope(Notebook).where(account_id: rodauth.rails_account.id).order(updated_at: :desc)
    @notebook_memo_counts = NotebookMemo.where(notebook_id: @notebooks.map(&:id)).group(:notebook_id).count
  end

  def show
    authorize @notebook
    load_notebook_memos
    @can_manage = policy(@notebook).manage_memos?
  end

  def new
    @notebook = Notebook.new(account: rodauth.rails_account, publication_kind: :notes)
    authorize @notebook
    prepare_directory_options
  end

  def create
    @notebook = Notebook.new(notebook_params.merge(account: rodauth.rails_account))
    authorize @notebook
    if @notebook.save
      redirect_to @notebook, notice: "ノートブックを作成しました。"
    else
      prepare_directory_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @notebook
    prepare_directory_options
    load_notebook_memos
    load_available_memos if policy(@notebook).manage_memos?
  end

  def update
    authorize @notebook
    if @notebook.update(notebook_params)
      redirect_to @notebook, notice: "ノートブックを更新しました。"
    else
      prepare_directory_options
      load_notebook_memos
      load_available_memos
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @notebook
    @notebook.destroy
    redirect_to notebooks_path, notice: "ノートブックを削除しました。", status: :see_other
  end

  def publish
    authorize @notebook, :publish?
    Notebooks::Publish.call(notebook: @notebook)
    redirect_to @notebook, notice: "ノートブックを公開しました。"
  rescue Notebooks::Error => e
    redirect_to @notebook, alert: e.message
  end

  def unpublish
    authorize @notebook, :unpublish?
    @notebook.update!(published_at: nil)
    redirect_to @notebook, notice: "公開を停止しました。"
  end

  def available_memos
    authorize @notebook, :available_memos?
    query = params[:q].to_s.strip
    memos = policy_scope(Memo).left_outer_joins(:notebook_memo).where(notebook_memos: { id: nil })
      .includes(:tags).order(updated_at: :desc).limit(20)
    memos = memos.search_text(query) if query.present?

    render json: memos.map { |memo|
      {
        id: memo.id,
        title: memo.title,
        updated_at: memo.updated_at.iso8601(3),
        tags: memo.tags.map(&:name)
      }
    }
  end

  def require_authentication
    return if action_name == "show"

    super
  end

  private

  def set_notebook
    @notebook = policy_scope(Notebook).find(params[:id])
  end

  def load_notebook_memos
    @notebook_memos = @notebook.notebook_memos
      .joins(:memo)
      .merge(policy_scope(Memo))
      .includes(:memo)
      .order(:position, :id)
  end

  def load_available_memos
    @available_memos = policy_scope(Memo).left_outer_joins(:notebook_memo).where(notebook_memos: { id: nil })
      .order(updated_at: :desc).limit(30)
  end

  def prepare_directory_options
    @memo_directory_options = policy_scope(MemoDirectory).nav_ordered.select(&:directory_picker_selectable?)
  end

  def notebook_params
    raw = params.require(:notebook).permit(:title, :slug, :publication_kind, :description, :memo_directory_id)
    if raw[:memo_directory_id].present?
      dir = policy_scope(MemoDirectory).find_by(id: raw[:memo_directory_id])
      raw[:memo_directory_id] = dir&.id
    end
    raw
  end
end
