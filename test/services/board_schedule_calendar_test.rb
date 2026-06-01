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

  test "includes google calendar synced memos not on the board" do
    gcal_memo = Memo.create!(
      account: @account,
      memo_directory: memo_directories(:work),
      title: "GCal standup",
      body: "",
      properties: {
        "scheduled_on" => "2026-05-15",
        "google_calendar" => {
          "event_id" => "evt-1",
          "calendar_id" => "primary",
          "starts_at" => "2026-05-15T10:00:00+09:00",
          "all_day" => false,
          "read_only" => true
        }
      }
    )

    calendar = BoardScheduleCalendar.new(
      board: @board,
      memos_scope: Memo.where(account_id: @account.id),
      month: Date.new(2026, 5, 1),
      selected_day: Date.new(2026, 5, 15)
    )

    assert_includes calendar.list_items, gcal_memo
    assert_includes calendar.dates_with_items, Date.new(2026, 5, 15)
  end

  test "excludes scheduled memos on other boards without google calendar sync" do
    other_board = Board.create!(account: @account, title: "Other")
    other_memo = memos(:two)
    BoardKanban::AddMemo.call(board: other_board, memo: other_memo, column: other_board.board_columns.first)
    other_memo.update!(scheduled_on: Date.new(2026, 5, 15))

    calendar = BoardScheduleCalendar.new(
      board: @board,
      memos_scope: Memo.where(account_id: @account.id),
      month: Date.new(2026, 5, 1),
      selected_day: Date.new(2026, 5, 15)
    )

    assert_not_includes calendar.list_items, other_memo
  end

  test "week view groups memos within selected week" do
    @memo.update!(scheduled_on: Date.new(2026, 5, 15))
    other = memos(:two)
    BoardKanban::AddMemo.call(board: @board, memo: other, column: board_columns(:one_todo))
    other.update!(scheduled_on: Date.new(2026, 5, 17))

    calendar = BoardScheduleCalendar.new(
      board: @board,
      memos_scope: Memo.where(account_id: @account.id),
      month: Date.new(2026, 5, 1),
      selected_day: Date.new(2026, 5, 15),
      view: "week"
    )

    assert calendar.week_view?
    assert_equal 2, calendar.list_groups.sum { |group| group[:memos].size }
    assert_includes calendar.list_groups.flat_map { |g| g[:memos] }, @memo
    assert_includes calendar.list_groups.flat_map { |g| g[:memos] }, other
  end

  test "month view groups all scheduled memos in month" do
    @memo.update!(scheduled_on: Date.new(2026, 5, 15))

    calendar = BoardScheduleCalendar.new(
      board: @board,
      memos_scope: Memo.where(account_id: @account.id),
      month: Date.new(2026, 5, 1),
      selected_day: Date.new(2026, 5, 1),
      view: "month"
    )

    assert calendar.month_view?
    assert_equal 1, calendar.list_groups.size
    assert_equal [@memo], calendar.list_groups.first[:memos]
  end

  test "invalid view falls back to day" do
    calendar = BoardScheduleCalendar.new(
      board: @board,
      memos_scope: Memo.where(account_id: @account.id),
      month: Date.new(2026, 5, 1),
      selected_day: Date.new(2026, 5, 15),
      view: "year"
    )

    assert calendar.day_view?
  end

  test "recurring google calendar memo appears on each occurrence in week view" do
    gcal_memo = Memo.create!(
      account: @account,
      memo_directory: memo_directories(:work),
      title: "Weekly standup",
      body: "",
      properties: {
        "scheduled_on" => "2026-05-06",
        "google_calendar" => {
          "event_id" => "evt-weekly",
          "calendar_id" => "primary",
          "starts_at" => "2026-05-07T10:00:00+09:00",
          "recurrence" => [ "RRULE:FREQ=WEEKLY;BYDAY=WE" ],
          "recurring" => true,
          "all_day" => false,
          "read_only" => true
        }
      }
    )

    calendar = BoardScheduleCalendar.new(
      board: @board,
      memos_scope: Memo.where(account_id: @account.id),
      month: Date.new(2026, 5, 1),
      selected_day: Date.new(2026, 5, 7),
      view: "week"
    )

    wednesdays = calendar.list_groups.select { |group| group[:date].wednesday? }.flat_map { |group| group[:memos] }
    assert wednesdays.count >= 2
    assert wednesdays.all? { |memo| memo == gcal_memo }
  end
end
