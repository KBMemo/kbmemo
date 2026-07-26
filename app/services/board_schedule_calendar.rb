# frozen_string_literal: true

# 月カレンダーと選択日の予定一覧。board が nil の場合は全カンバンを対象にする。
class BoardScheduleCalendar
  WEEKDAY_LABELS = %w[月 火 水 木 金 土 日].freeze
  VIEWS = %w[day week month].freeze
  Occurrence = Data.define(:memo, :date)

  attr_reader :board, :month, :selected_day, :weeks, :dates_with_items, :list_items, :view, :list_groups

  def initialize(board:, memos_scope:, month:, selected_day: nil, view: "day")
    @board = board
    @view = normalize_view(view)
    @month = month.to_date.beginning_of_month
    @selected_day = normalize_selected_day(selected_day)
    @scheduled_memos = load_scheduled_memos(memos_scope)
    month_range = @month..@month.end_of_month
    @month_occurrences = occurrences_in_range(@scheduled_memos, month_range)
    @dates_with_items = @month_occurrences.map(&:date).to_set
    @list_items = items_for_day(@selected_day)
    @list_groups = build_list_groups
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

  def day_view?
    view == "day"
  end

  def week_view?
    view == "week"
  end

  def month_view?
    view == "month"
  end

  def week_start
    @selected_day.beginning_of_week(:monday)
  end

  def week_end
    @selected_day.end_of_week(:monday)
  end

  def prev_week_day
    week_start - 7
  end

  def next_week_day
    week_start + 7
  end

  def list_empty?
    day_view? ? list_items.empty? : list_groups.empty?
  end

  private

  def normalize_view(raw)
    view = raw.to_s.presence || "day"
    VIEWS.include?(view) ? view : "day"
  end

  def items_for_day(day)
    occurrences_in_range(@scheduled_memos, day..day)
      .sort_by { |occurrence| schedule_sort_key(occurrence) }
      .map(&:memo)
  end

  def build_list_groups
    range =
      case view
      when "week"
        week_start..week_end
      when "month"
        @month..@month.end_of_month
      else
        return []
      end

    occurrences_in_range(@scheduled_memos, range)
      .group_by(&:date)
      .sort_by { |date, _| date }
      .map do |date, occurrences|
        {
          date: date,
          memos: occurrences.sort_by { |occurrence| schedule_sort_key(occurrence) }.map(&:memo)
        }
      end
  end

  def occurrences_in_range(memos, range)
    memos.flat_map { |memo| occurrences_for_memo(memo, range) }
  end

  def occurrences_for_memo(memo, range)
    GoogleCalendar::Occurrences.dates_in_range(memo, range).map do |date|
      Occurrence.new(memo: memo, date: date)
    end
  end

  # ボード上カード（scheduled_on あり）と Google Calendar 同期メモ（board 外）を含める。
  def load_scheduled_memos(memos_scope)
    scheduled_on_sql = MemoPropertiesSql.json_text_at("scheduled_on")
    gcal_event_sql = MemoPropertiesSql.json_text_at("google_calendar", "event_id")
    board_memos = memos_scope
      .where("#{scheduled_on_sql} IS NOT NULL AND #{scheduled_on_sql} != ''")
      .includes(:kanban_column)
    board_memos = board_memos.where(board_id: board.id) if board
    gcal_memos = memos_scope
      .where("#{gcal_event_sql} IS NOT NULL AND #{gcal_event_sql} != ''")
      .includes(:kanban_column)
      .to_a
    (board_memos.to_a + gcal_memos).uniq
  end

  def schedule_sort_key(occurrence)
    memo = occurrence.memo
    starts_at = memo.properties.dig("google_calendar", "starts_at")
    sort_time =
      if starts_at.present?
        Time.zone.parse(starts_at.to_s)
      else
        occurrence.date
      end
    [ occurrence.date, sort_time, memo.title.to_s ]
  rescue ArgumentError, TypeError
    [ occurrence.date, occurrence.date, memo.title.to_s ]
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
