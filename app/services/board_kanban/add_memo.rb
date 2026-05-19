# frozen_string_literal: true

module BoardKanban
  class AddMemo
    def self.call(board:, memo:, column: nil)
      new(board: board, memo: memo, column: column).call
    end

    def initialize(board:, memo:, column: nil)
      @board = board
      @memo = memo
      @column = column
    end

    def call
      raise Error, "このメモは既に別のボードに載っています" if @memo.board_id.present? && @memo.board_id != @board.id

      target_column = @column || @board.board_columns.order(:position).first!
      position = next_position_in(target_column)

      @memo.update!(
        board_id: @board.id,
        kanban_column_id: target_column.id,
        kanban_position: position
      )
      @memo
    end

    private

    def next_position_in(column)
      @board.memos.where(kanban_column_id: column.id).maximum(:kanban_position).to_i + 1
    end
  end
end
