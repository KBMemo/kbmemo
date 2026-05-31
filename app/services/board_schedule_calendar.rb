# frozen_string_literal: true

# カンバンボード左サイドバー用: 月カレンダーと選択日の予定一覧。
class BoardScheduleCalendar
  WEEKDAY_LABELS = %w[月 火 水 木 金 土 日].freeze

  attr_reader :board, :month, :selected_day, :weeks, :dates_with_items, :list_items

  def initialize(board:, memos_scope:, month:, selected_day: nil)
    @board = board
    @month = month.to_date.beginning_of_month
    @selected_day = normalize_selected_day(selected_day)
    scheduled = load_scheduled_memos(memos_scope)
    month_range = @month..@month.end_of_month
    @month_memos = scheduled
      .select { |memo| month_range.cover?(memo.scheduled_on) }
      .sort_by { |memo| schedule_sort_key(memo) }
    @dates_with_items = @month_memos.map(&:scheduled_on).to_set
    @list_items = scheduled
      .select { |memo| memo.scheduled_on == @selected_day }
      .sort_by { |memo| schedule_sort_key(memo) }
    @weeks = build_weeks
  end

  def prev_month
    @month.prev_month
  end

  def next_month
    @month.next_month
  end

  def today?(day)
    day == Date.current
  end

  def selected?(day)
    day == @selected_day
  end

  def in_month?(day)
    day.month == @month.month && day.year == @month.year
  end

  def scheduled?(day)
    @dates_with_items.include?(day)
  end

  private

  # ボード上カード（scheduled_on あり）と Google Calendar 同期メモ（board 外）を含める。
  def load_scheduled_memos(memos_scope)
    scheduled_on_sql = MemoPropertiesSql.json_text_at("scheduled_on")
    gcal_event_sql = MemoPropertiesSql.json_text_at("google_calendar", "event_id")
    memos_scope
      .where("#{scheduled_on_sql} IS NOT NULL AND #{scheduled_on_sql} != ''")
      .where(
        "memos.board_id = ? OR (#{gcal_event_sql} IS NOT NULL AND #{gcal_event_sql} != '')",
        board.id
      )
      .includes(:kanban_column)
      .to_a
  end

  def schedule_sort_key(memo)
    starts_at = memo.properties.dig("google_calendar", "starts_at")
    sort_time =
      if starts_at.present?
        Time.zone.parse(starts_at.to_s)
      else
        memo.scheduled_on
      end
    [ memo.scheduled_on, sort_time, memo.title.to_s ]
  rescue ArgumentError, TypeError
    [ memo.scheduled_on, memo.scheduled_on, memo.title.to_s ]
  end

  def normalize_selected_day(day)
    candidate = day.presence || Date.current
    candidate = candidate.to_date
    return candidate if candidate.month == @month.month && candidate.year == @month.year

    if @month.month == Date.current.month && @month.year == Date.current.year
      Date.current
    else
      @month
    end
  end

  def build_weeks
    start_day = @month.beginning_of_week(:monday)
    end_day = @month.end_of_month.end_of_week(:monday)
    (start_day..end_day).to_a.each_slice(7).to_a
  end
end
