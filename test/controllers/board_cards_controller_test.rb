# frozen_string_literal: true

require "test_helper"

class BoardCardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @board = boards(:one)
    @todo = board_columns(:one_todo)
  end

  test "create adds existing memo" do
    memo = memos(:one)
    assert_nil memo.board_id

    post board_board_cards_url(@board),
      params: { memo_id: memo.id, kanban_column_id: @todo.id },
      headers: { Accept: "text/vnd.turbo-stream.html" }

    assert_response :success
    memo.reload
    assert_equal @board.id, memo.board_id
    assert_equal @todo.id, memo.kanban_column_id
  end

  test "create new card memo" do
    assert_difference("Memo.count", 1) do
      post board_board_cards_url(@board),
        params: { title: "Kanban task", kanban_column_id: @todo.id },
        headers: { Accept: "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    memo = Memo.order(:id).last
    assert_equal @board.id, memo.board_id
    assert_equal "Kanban task", memo.title
  end

  test "destroy removes card from board" do
    memo = memos(:one)
    BoardKanban::AddMemo.call(board: @board, memo: memo, column: @todo)

    delete board_board_card_url(@board, memo), headers: { Accept: "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_nil memo.reload.board_id
  end
end
