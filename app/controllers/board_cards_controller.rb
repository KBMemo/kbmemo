# frozen_string_literal: true

class BoardCardsController < ApplicationController
  after_action :verify_authorized

  before_action :set_board

  def create
    authorize @board, :update?

    if params[:memo_id].present?
      memo = policy_scope(Memo).available_for_board.find(params[:memo_id])
      authorize memo, :update?
      column = find_column
      BoardKanban::AddMemo.call(board: @board, memo: memo, column: column)
      @memo = memo
    else
      column = find_column
      authorize Memo.new(account: rodauth.rails_account), :create?
      @memo = BoardKanban::CreateCard.call(
        board: @board,
        account: rodauth.rails_account,
        title: params[:title],
        column: column
      )
    end

    load_kanban_data

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @board, notice: "カードを追加しました。" }
    end
  rescue BoardKanban::Error => e
    respond_to do |format|
      format.turbo_stream { head :unprocessable_entity }
      format.html { redirect_to @board, alert: e.message }
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def destroy
    memo = policy_scope(Memo).find(params[:id])
    authorize memo, :update?
    authorize @board, :update?

    BoardKanban::RemoveCard.call(board: @board, memo: memo)
    @memo = memo
    load_kanban_data

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @board, notice: "ボードからカードを外しました。" }
    end
  rescue BoardKanban::Error => e
    respond_to do |format|
      format.turbo_stream { head :unprocessable_entity }
      format.html { redirect_to @board, alert: e.message }
    end
  end

  private

  def set_board
    @board = policy_scope(Board).find(params[:board_id])
  end

  def find_column
    return @board.board_columns.order(:position).first! if params[:kanban_column_id].blank?

    @board.board_columns.find(params[:kanban_column_id])
  end

  def load_kanban_data
    visible_ids = policy_scope(Memo).where(board_id: @board.id).pluck(:id)
    @board_columns = @board.board_columns.includes(memos: :tags).order(:position)
    @visible_memo_ids = visible_ids.to_set
  end
end
