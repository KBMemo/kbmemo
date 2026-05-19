# frozen_string_literal: true

class BoardsController < ApplicationController
  after_action :verify_authorized

  before_action :set_board, only: %i[show edit update destroy move_card available_memos]

  def index
    authorize Board
    @boards = policy_scope(Board).order(updated_at: :desc)
    @board_memo_counts = Memo.where(board_id: @boards.map(&:id)).group(:board_id).count
  end

  def show
    authorize @board
    load_kanban_data
  end

  def new
    @board = Board.new(account: rodauth.rails_account)
    authorize @board
    prepare_directory_options
  end

  def create
    @board = Board.new(board_params.merge(account: rodauth.rails_account))
    authorize @board
    if @board.save
      redirect_to @board, notice: "ボードを作成しました。"
    else
      prepare_directory_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @board
    prepare_directory_options
    @board_columns = @board.board_columns.order(:position)
  end

  def update
    authorize @board
    if @board.update(board_params)
      redirect_to @board, notice: "ボードを更新しました。"
    else
      prepare_directory_options
      @board_columns = @board.board_columns.order(:position)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @board
    @board.destroy
    redirect_to boards_path, notice: "ボードを削除しました。", status: :see_other
  end

  def move_card
    authorize @board, :move_card?
    memo = policy_scope(Memo).find(params.require(:memo_id))
    authorize memo, :update?
    column = @board.board_columns.find(params.require(:kanban_column_id))

    BoardKanban::MoveCard.call(
      board: @board,
      memo: memo,
      column: column,
      position: params[:kanban_position]
    )
    load_kanban_data

    respond_to do |format|
      format.turbo_stream { render :move_card }
      format.json { render json: { ok: true } }
    end
  rescue BoardKanban::Error => e
    respond_to do |format|
      format.turbo_stream { head :unprocessable_entity }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def available_memos
    authorize @board, :available_memos?
    query = params[:q].to_s.strip
    memos = policy_scope(Memo).available_for_board.includes(:tags).order(updated_at: :desc).limit(20)
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

  private

  def set_board
    @board = policy_scope(Board).find(params[:id])
  end

  def load_kanban_data
    visible_ids = policy_scope(Memo).where(board_id: @board.id).pluck(:id)
    @board_columns = @board.board_columns.includes(memos: :tags).order(:position)
    @visible_memo_ids = visible_ids.to_set
  end

  def prepare_directory_options
    @memo_directory_options = policy_scope(MemoDirectory).nav_ordered.select(&:directory_picker_selectable?)
  end

  def board_params
    raw = params.require(:board).permit(:title, :memo_directory_id)
    if raw[:memo_directory_id].present?
      dir = policy_scope(MemoDirectory).find_by(id: raw[:memo_directory_id])
      raw[:memo_directory_id] = dir&.id
    end
    raw
  end
end
