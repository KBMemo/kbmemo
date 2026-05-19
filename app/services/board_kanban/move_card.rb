# frozen_string_literal: true

module BoardKanban
  class MoveCard
    def self.call(board:, memo:, column:, position:)
      new(board: board, memo: memo, column: column, position: position).call
    end

    def self.compact_column!(board:, column_id:)
      memos = board.memos.where(kanban_column_id: column_id).order(:kanban_position, :id)
      memos.each_with_index do |memo, index|
        memo.update_column(:kanban_position, index) if memo.kanban_position != index
      end
    end

    def initialize(board:, memo:, column:, position:)
      @board = board
      @memo = memo
      @column = column
      @position = position.to_i
    end

    def call
      raise Error, "このメモはボードに載っていません" unless @memo.board_id == @board.id
      raise Error, "列がボードに属していません" unless @column.board_id == @board.id

      old_column_id = @memo.kanban_column_id

      ActiveRecord::Base.transaction do
        @memo.update!(kanban_column_id: @column.id, board_id: @board.id)
        reorder_column!(@column.id, @memo.id, @position)
        if old_column_id.present? && old_column_id != @column.id
          self.class.compact_column!(board: @board, column_id: old_column_id)
        end
      end

      @memo.reload
    end

    private

    def reorder_column!(column_id, inserted_memo_id, insert_at)
      memos = @board.memos.where(kanban_column_id: column_id).order(:kanban_position, :id).to_a
      memos.reject! { |m| m.id == inserted_memo_id } if inserted_memo_id

      if inserted_memo_id
        insert_index = [ insert_at, memos.size ].min
        memo = @board.memos.find(inserted_memo_id)
        memos.insert(insert_index, memo)
      end

      memos.each_with_index do |memo, index|
        memo.update_column(:kanban_position, index) if memo.kanban_position != index
      end
    end
  end
end
