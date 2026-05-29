# frozen_string_literal: true

class NotebookMemosController < ApplicationController
  after_action :verify_authorized

  before_action :set_notebook

  def create
    authorize @notebook, :manage_memos?

    memo = policy_scope(Memo).find(params.require(:memo_id))
    authorize memo, :add_to_notebook?

    Notebooks::AddMemo.call(notebook: @notebook, memo: memo)
    redirect_to notebook_path(@notebook, memo_id: memo.id), notice: "メモを追加しました。"
  rescue Notebooks::Error => e
    redirect_to edit_notebook_path(@notebook), alert: e.message
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def create_blank
    authorize @notebook, :manage_memos?

    memo = Memo.new(account: rodauth.rails_account, memo_directory_id: default_memo_directory_id)
    authorize memo, :create?
    memo.save!

    Notebooks::AddMemo.call(notebook: @notebook, memo: memo)
    redirect_to edit_memo_path(memo), notice: "メモを作成して末尾に追加しました。"
  rescue Notebooks::Error => e
    redirect_to notebook_path(@notebook), alert: e.message
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

  def default_memo_directory_id
    MemoDirectory::UserSpace.default_home_directory(rodauth.rails_account.id).id
  end
end
