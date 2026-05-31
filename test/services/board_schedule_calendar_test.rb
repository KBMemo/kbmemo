# frozen_string_literal: true

require "test_helper"

class BoardScheduleCalendarTest < ActiveSupport::TestCase
  setup do
    @board = boards(:one)
    @account = accounts(:one)
    @memo = memos(:one)
    BoardKanban::AddMemo.call(board: @board, memo: @memo, column: board_columns(:one_todo))
    @memo.update!(scheduled_on: Date.new(2026, 5, 15))
  end

  test "lists memos scheduled on selected day within month" do
    calendar = BoardScheduleCalendar.new(
      board: @board,
      memos_scope: Memo.where(account_id: @account.id),
      month: Date.new(2026, 5, 1),
      selected_day: Date.new(2026, 5, 15)
    )

    assert_includes calendar.dates_with_items, Date.new(2026, 5, 15)
    assert_equal [@memo], calendar.list_items
    assert_operator calendar.weeks.size, :>=, 4
  end

  test "defaults selected day to today when viewing current month" do
    travel_to Time.zone.local(2026, 5, 20, 12, 0, 0) do
      @memo.update!(scheduled_on: Date.new(2026, 5, 20))
      calendar = BoardScheduleCalendar.new(
        board: @board,
        memos_scope: Memo.where(account_id: @account.id),
        month: Date.new(2026, 5, 1),
        selected_day: nil
      )

      assert_equal Date.new(2026, 5, 20), calendar.selected_day
      assert_equal [@memo], calendar.list_items
    end
  end
end
