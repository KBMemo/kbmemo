# frozen_string_literal: true

class DashboardOverview
  LIMIT = 5
  SCHEDULE_DAYS = 90
  ScheduleEntry = Data.define(:memo, :date)

  attr_reader :latest_memos, :tasks, :schedule, :recent_notebooks

  def initialize(account:, memo_scope:, board_scope:, notebook_scope:, today: Date.current)
    @account = account
    @memo_scope = memo_scope.where(account_id: account.id)
    @board_scope = board_scope.where(account_id: account.id)
    @notebook_scope = notebook_scope.where(account_id: account.id)
    @today = today

    @latest_memos = load_latest_memos
    @tasks = load_tasks
    @schedule = load_schedule
    @recent_notebooks = load_recent_notebooks
  end

  private

  def load_latest_memos
    @memo_scope.includes(:tags).order(updated_at: :desc, id: :desc).limit(LIMIT)
  end

  def load_tasks
    boards = @board_scope.includes(:board_columns).to_a
    done_column_ids = boards.filter_map { |board| board.board_columns.max_by(&:position)&.id }

    candidates = @memo_scope
      .where(board_id: boards.map(&:id))
      .where.not(kanban_column_id: done_column_ids)
      .includes(:board, :kanban_column)
      .order(updated_at: :desc)
      .limit(50)
      .to_a

    candidates.sort_by do |memo|
      [ memo.scheduled_on ? 0 : 1, memo.scheduled_on || Date.new(9999, 12, 31), -memo.updated_at.to_i ]
    end.first(LIMIT)
  end

  def load_schedule
    scheduled_on_sql = MemoPropertiesSql.json_text_at("scheduled_on")
    range = @today..(@today + SCHEDULE_DAYS.days)

    @memo_scope
      .where("#{scheduled_on_sql} IS NOT NULL AND #{scheduled_on_sql} != ''")
      .includes(:board)
      .find_each
      .flat_map do |memo|
        GoogleCalendar::Occurrences.dates_in_range(memo, range).map do |date|
          ScheduleEntry.new(memo: memo, date: date)
        end
      end
      .sort_by { |entry| [ entry.date, entry.memo.title.to_s ] }
      .first(LIMIT)
  end

  def load_recent_notebooks
    @notebook_scope
      .left_joins(:memos)
      .select(
        "notebooks.*",
        "GREATEST(notebooks.updated_at, COALESCE(MAX(memos.updated_at), notebooks.updated_at)) AS activity_at"
      )
      .group("notebooks.id")
      .order(Arel.sql("activity_at DESC"), id: :desc)
      .limit(LIMIT)
  end
end
