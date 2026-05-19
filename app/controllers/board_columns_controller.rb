# frozen_string_literal: true

class BoardColumnsController < ApplicationController
  after_action :verify_authorized

  before_action :set_board
  before_action :set_board_column

  def update
    authorize @board_column
    if @board_column.update(board_column_params)
      redirect_to edit_board_path(@board), notice: "列を更新しました。"
    else
      redirect_to edit_board_path(@board), alert: @board_column.errors.full_messages.to_sentence
    end
  end

  def swap
    authorize @board_column, :swap?
    other = @board.board_columns.find(params.require(:other_column_id))
    @board_column.swap_position_with!(other)
    redirect_to edit_board_path(@board), notice: "列の順序を変更しました。"
  rescue ArgumentError => e
    redirect_to edit_board_path(@board), alert: e.message
  end

  private

  def set_board
    @board = policy_scope(Board).find(params[:board_id])
  end

  def set_board_column
    @board_column = @board.board_columns.find(params[:id])
  end

  def board_column_params
    params.require(:board_column).permit(:name)
  end
end
