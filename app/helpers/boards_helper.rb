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
end
