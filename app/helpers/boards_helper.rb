# frozen_string_literal: true

module BoardsHelper
  def kanban_card_checklist_progress(memo)
    boxes = Array(memo.properties["checkboxes"])
    return nil if boxes.empty?

    done = boxes.count { |row| row["checked"] }
    "#{done}/#{boxes.size}"
  end

  def kanban_column_memos(column, visible_memo_ids)
    column.memos.select { |memo| visible_memo_ids.include?(memo.id) }
          .sort_by { |memo| [ memo.kanban_position, memo.id ] }
  end

  def board_schedule_path(board, month:, day:, view: "day")
    board_path(
      board,
      schedule_month: month.to_date.strftime("%Y-%m"),
      schedule_day: day.to_date.strftime("%Y-%m-%d"),
      schedule_view: view
    )
  end

  def board_schedule_month_path(board, month, selected_day: nil, view: nil)
    day = selected_day || default_schedule_day_for_month(month)
    board_schedule_path(
      board,
      month: month,
      day: day,
      view: view || current_board_schedule_view
    )
  end

  def board_schedule_day_path(board, day, view: nil)
    board_schedule_path(
      board,
      month: day.beginning_of_month,
      day: day,
      view: view || current_board_schedule_view
    )
  end

  def board_schedule_week_path(board, week_anchor_day, view: "week")
    board_schedule_path(
      board,
      month: week_anchor_day.beginning_of_month,
      day: week_anchor_day,
      view: view
    )
  end

  def board_schedule_view_tab_path(board, view)
    calendar = @schedule_calendar
    day = calendar&.selected_day || Date.current
    month = calendar&.month || day.beginning_of_month
    board_schedule_path(board, month: month, day: day, view: view)
  end

  def board_schedule_view_tab_classes(view)
    base = "kb-sidebar-tab #{kb_focus_ring}"
    active = @schedule_calendar&.view == view
    [ base, active ? "is-active" : nil ].compact.join(" ")
  end

  def board_schedule_list_heading(calendar)
    if calendar.week_view?
      if calendar.week_start.month == calendar.week_end.month && calendar.week_start.year == calendar.week_end.year
        "#{calendar.week_start.strftime('%-m月%-d日')} – #{calendar.week_end.strftime('%-d日')}"
      else
        "#{l(calendar.week_start, format: :short)} – #{l(calendar.week_end, format: :short)}"
      end
    elsif calendar.month_view?
      board_schedule_month_label(calendar.month)
    else
      l(calendar.selected_day, format: :long)
    end
  end

  def board_schedule_month_label(month)
    month.strftime("%Y年%-m月")
  end

  def board_schedule_item_meta(memo)
    if memo.google_calendar_synced?
      gcal = memo.properties.fetch("google_calendar", {})
      label = "Google Calendar"
      if gcal["all_day"]
        label = "#{label} · 終日"
      elsif gcal["starts_at"].present?
        time = Time.zone.parse(gcal["starts_at"].to_s)
        label = "#{label} · #{time.strftime('%H:%M')}"
      end
      label = "#{label} · 繰り返し" if memo.google_calendar_recurring?
      label
    elsif memo.kanban_column
      memo.kanban_column.name
    end
  end

  def board_schedule_day_cell_classes(calendar, day)
    classes = [
      "kb-board-schedule-day",
      "flex h-8 w-8 items-center justify-center rounded-md text-sm",
      "hover:bg-[color-mix(in_srgb,var(--kb-bg-muted)_85%,transparent)]"
    ]
    classes << "kb-text-subtle" unless calendar.in_month?(day)
    classes << "font-semibold ring-1 ring-[var(--kb-border-strong)]" if calendar.today?(day)
    classes << "bg-[color-mix(in_srgb,var(--kb-accent)_18%,transparent)] font-semibold kb-text-primary" if calendar.selected?(day)
    classes << "kb-board-schedule-day--has-items font-medium" if calendar.scheduled?(day)
    classes.join(" ")
  end

  private

  def current_board_schedule_view
    @schedule_calendar&.view.presence || "day"
  end

  def default_schedule_day_for_month(month)
    month_date = month.to_date.beginning_of_month
    if month_date.month == Date.current.month && month_date.year == Date.current.year
      Date.current
    else
      month_date
    end
  end
end
