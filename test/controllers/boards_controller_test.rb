# frozen_string_literal: true

require "test_helper"

class BoardsControllerTest < ActionDispatch::IntegrationTest
  test "index lists boards" do
    get boards_url
    assert_response :success
    assert_includes response.body, boards(:one).title
    assert_select "[data-user-menu-target='panel'] a[href=?]", board_path(boards(:one))
    assert_select "[data-user-menu-target='panel'] a[href=?]", boards_path
  end

  test "show renders kanban" do
    board = boards(:one)
    BoardKanban::AddMemo.call(board: board, memo: memos(:one), column: board_columns(:one_todo))

    get board_url(board)
    assert_response :success
    assert_includes response.body, board_columns(:one_todo).name
    assert_select "dialog#board_add_memo_panel[aria-labelledby='board-add-memo-title']"
    assert_select "#board-add-memo-title", text: "既存メモを追加"
    assert_select "search label.sr-only[for='q']", text: "追加する既存メモを検索"
    assert_select "search input[type='search'][data-board-add-memo-target='query']"
    assert_select ".kb-kanban-card button[aria-label='ドラッグ'].border-0.bg-transparent.p-0"
    assert_select ".kb-kanban-card button[title='ボードから外す'].border-0.bg-transparent.p-0"
  end

  test "show renders schedule sidebar with calendar" do
    get board_url(boards(:one))
    assert_response :success
    assert_select "#board_schedule_sidebar_shell"
    assert_select "#board_schedule_panel"
    assert_select ".kb-board-schedule-calendar"
    assert_select ".kb-board-schedule-list"
    assert_select ".kb-sidebar-tab-bar a", text: "日"
    assert_select ".kb-sidebar-tab-bar a", text: "週"
    assert_select ".kb-sidebar-tab-bar a", text: "月"
  end

  test "show renders week schedule view" do
    board = boards(:one)
    memo = memos(:one)
    BoardKanban::AddMemo.call(board: board, memo: memo, column: board_columns(:one_todo))
    memo.update!(scheduled_on: Date.new(2026, 5, 15))

    get board_url(board, schedule_month: "2026-05", schedule_day: "2026-05-15", schedule_view: "week")
    assert_response :success
    assert_includes response.body, memo.title
    assert_select ".kb-sidebar-tab.is-active", text: "週"
  end

  test "show lists scheduled memos for selected day" do
    board = boards(:one)
    memo = memos(:one)
    BoardKanban::AddMemo.call(board: board, memo: memo, column: board_columns(:one_todo))
    memo.update!(scheduled_on: Date.new(2026, 5, 15))

    get board_url(board, schedule_month: "2026-05", schedule_day: "2026-05-15")
    assert_response :success
    assert_includes response.body, memo.title
    assert_select ".kb-board-schedule-list ul.list-none.p-0"
  end

  test "create board with default columns" do
    assert_difference("Board.count", 1) do
      post boards_url, params: { board: { title: "New board" } }
    end
    board = Board.order(:id).last
    assert_redirected_to board_url(board)
    assert_equal 3, board.board_columns.count
  end

  test "move_card updates placement" do
    board = boards(:one)
    memo = memos(:one)
    BoardKanban::AddMemo.call(board: board, memo: memo, column: board_columns(:one_todo))

    patch move_card_board_url(board),
      params: {
        memo_id: memo.id,
        kanban_column_id: board_columns(:one_doing).id,
        kanban_position: 0
      },
      headers: { Accept: "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal board_columns(:one_doing).id, memo.reload.kanban_column_id
  end

  test "available_memos returns unassigned memos" do
    get available_memos_board_url(boards(:one)), headers: { Accept: "application/json" }
    assert_response :success
    ids = JSON.parse(response.body).map { |row| row["id"] }
    assert_includes ids, memos(:one).id
  end

  test "destroy board keeps memos" do
    board = boards(:one)
    memo = memos(:one)
    BoardKanban::AddMemo.call(board: board, memo: memo, column: board_columns(:one_todo))

    assert_difference("Memo.count", 0) do
      delete board_url(board)
    end
    assert_redirected_to boards_url
    assert_nil memo.reload.board_id
  end

  test "new board form has no directory picker" do
    get new_board_url
    assert_response :success
    assert_select "div##{'board_directory_picker'}", count: 0
    assert_select "input[type=hidden][name=?]", "board[memo_directory_id]", count: 0
  end

  test "cannot access other users board" do
    other_board = Board.create!(title: "Other", account: accounts(:two))
    get board_url(other_board)
    assert_response :not_found
  end
end
