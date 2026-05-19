# frozen_string_literal: true

module BoardKanban
  class CreateCard
    def self.call(board:, account:, title:, column: nil)
      new(board: board, account: account, title: title, column: column).call
    end

    def initialize(board:, account:, title:, column: nil)
      @board = board
      @account = account
      @title = title.to_s.strip
      @column = column
    end

    def call
      raise BoardKanban::Error, "タイトルを入力してください" if @title.blank?

      target_column = @column || @board.board_columns.order(:position).first!
      position = next_position_in(target_column)

      memo = Memo.new(
        title: @title,
        body: "",
        account: @account,
        memo_directory_id: @board.default_memo_directory_for(@account).id,
        board: @board,
        kanban_column: target_column,
        kanban_position: position
      )
      memo.save!
      memo
    end

    private

    def next_position_in(column)
      @board.memos.where(kanban_column_id: column.id).maximum(:kanban_position).to_i + 1
    end
  end
end
