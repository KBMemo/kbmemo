# frozen_string_literal: true

module BoardKanban
  class RemoveCard
    def self.call(board:, memo:)
      new(board: board, memo: memo).call
    end

    def initialize(board:, memo:)
      @board = board
      @memo = memo
    end

    def call
      raise Error, "このメモはボードに載っていません" unless @memo.board_id == @board.id

      column_id = @memo.kanban_column_id

      ActiveRecord::Base.transaction do
        @memo.update!(board_id: nil, kanban_column_id: nil, kanban_position: 0)
        MoveCard.compact_column!(board: @board, column_id: column_id) if column_id.present?
      end

      @memo
    end
  end
end
