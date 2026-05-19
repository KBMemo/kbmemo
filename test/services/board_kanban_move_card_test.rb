# frozen_string_literal: true

require "test_helper"

class BoardKanbanMoveCardTest < ActiveSupport::TestCase
  setup do
    @board = boards(:one)
    @todo = board_columns(:one_todo)
    @doing = board_columns(:one_doing)
    @memo = memos(:one)
    BoardKanban::AddMemo.call(board: @board, memo: @memo, column: @todo)
  end

  test "moves card to another column" do
    BoardKanban::MoveCard.call(board: @board, memo: @memo, column: @doing, position: 0)
    @memo.reload
    assert_equal @doing.id, @memo.kanban_column_id
    assert_equal 0, @memo.kanban_position
  end

  test "reorders within column" do
    other = memos(:two)
    BoardKanban::AddMemo.call(board: @board, memo: other, column: @todo)

    BoardKanban::MoveCard.call(board: @board, memo: other, column: @todo, position: 0)
    @memo.reload
    other.reload
    assert_equal 0, other.kanban_position
    assert_equal 1, @memo.kanban_position
  end
end
