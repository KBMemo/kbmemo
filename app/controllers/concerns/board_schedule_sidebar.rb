# frozen_string_literal: true

module BoardScheduleSidebar
  extend ActiveSupport::Concern

  private

  def load_board_schedule_sidebar(board)
    month = parse_schedule_month(params[:schedule_month])
    selected_day = parse_schedule_day(params[:schedule_day], month: month)
    @schedule_calendar = BoardScheduleCalendar.new(
      board: board,
      memos_scope: policy_scope(Memo),
      month: month,
      selected_day: selected_day,
      view: parse_schedule_view(params[:schedule_view])
    )
  end

  def parse_schedule_month(raw)
    return Date.current.beginning_of_month if raw.blank?

    Date.strptime(raw.to_s, "%Y-%m")
  rescue ArgumentError
    Date.current.beginning_of_month
  end

  def parse_schedule_day(raw, month:)
    return nil if raw.blank?

    Date.strptime(raw.to_s, "%Y-%m-%d")
  rescue ArgumentError
    nil
  end

  def parse_schedule_view(raw)
    view = raw.to_s.presence || "day"
    BoardScheduleCalendar::VIEWS.include?(view) ? view : "day"
  end
end
