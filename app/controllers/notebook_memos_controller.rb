# frozen_string_literal: true

class NotebookMemosController < ApplicationController
  after_action :verify_authorized

  before_action :set_notebook

  def create
    authorize @notebook, :manage_memos?

    memo = policy_scope(Memo).find(params.require(:memo_id))
    authorize memo, :update?

    Notebooks::AddMemo.call(notebook: @notebook, memo: memo)
    redirect_to notebook_path(@notebook, memo_id: memo.id), notice: "メモを追加しました。"
  rescue Notebooks::Error => e
    redirect_to edit_notebook_path(@notebook), alert: e.message
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def destroy
    authorize @notebook, :manage_memos?

    memo = policy_scope(Memo).find(params[:id])
    Notebooks::RemoveMemo.call(notebook: @notebook, memo: memo)
    redirect_to @notebook, notice: "メモをノートブックから外しました。"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def set_notebook
    @notebook = policy_scope(Notebook).find(params[:notebook_id])
  end
end
