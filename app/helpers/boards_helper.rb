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

  def board_schedule_month_path(board, month, selected_day: nil)
    day = selected_day || default_schedule_day_for_month(month)
    board_path(
      board,
      schedule_month: month.strftime("%Y-%m"),
      schedule_day: day.strftime("%Y-%m-%d")
    )
  end

  def board_schedule_day_path(board, day)
    board_path(
      board,
      schedule_month: day.strftime("%Y-%m"),
      schedule_day: day.strftime("%Y-%m-%d")
    )
  end

  def board_schedule_month_label(month)
    month.strftime("%Y年%-m月")
  end

  def board_schedule_item_meta(memo)
    if memo.google_calendar_synced?
      gcal = memo.properties.fetch("google_calendar", {})
      label = "Google Calendar"
      if gcal["all_day"]
        "#{label} · 終日"
      elsif gcal["starts_at"].present?
        time = Time.zone.parse(gcal["starts_at"].to_s)
        "#{label} · #{time.strftime('%H:%M')}"
      else
        label
      end
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

  def default_schedule_day_for_month(month)
    month_date = month.to_date.beginning_of_month
    if month_date.month == Date.current.month && month_date.year == Date.current.year
      Date.current
    else
      month_date
    end
  end
end
