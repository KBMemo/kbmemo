# frozen_string_literal: true

require "test_helper"

class DashboardOverviewTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @board = boards(:one)
  end

  test "loads recent memos, unfinished tasks, schedule, and active notebooks" do
    task = memos(:one)
    done = memos(:two)
    BoardKanban::AddMemo.call(board: @board, memo: task, column: board_columns(:one_todo))
    BoardKanban::AddMemo.call(board: @board, memo: done, column: board_columns(:one_done))
    task.update!(scheduled_on: Date.new(2026, 7, 25))
    notebooks(:one).update_column(:updated_at, 2.days.ago)
    task.update_column(:updated_at, 1.hour.from_now)

    overview = build_overview(today: Date.new(2026, 7, 24))

    assert_equal task, overview.latest_memos.first
    assert_includes overview.tasks, task
    assert_not_includes overview.tasks, done
    assert_equal [ task ], overview.schedule.map(&:memo)
    assert_equal [ Date.new(2026, 7, 25) ], overview.schedule.map(&:date)
    assert_equal notebooks(:one), overview.recent_notebooks.first
    assert_operator overview.latest_memos.size, :<=, DashboardOverview::LIMIT
  end

  test "does not include another account data" do
    other = memos(:two)
    other.update_columns(account_id: accounts(:two).id, updated_at: 1.minute.from_now)

    overview = build_overview

    assert_not_includes overview.latest_memos, other
  end

  private

  def build_overview(today: Date.current)
    DashboardOverview.new(
      account: @account,
      memo_scope: Memo.all,
      board_scope: Board.all,
      notebook_scope: Notebook.all,
      today: today
    )
  end
end
