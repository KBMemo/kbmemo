# frozen_string_literal: true

# AsciiDoc の [%interactive] チェックリストと memo.properties["checkboxes"] を同期する。
# 本文がラベル・[ ]/[x] の正本。properties には id・label（本文からコピー）・checked を保持する。
class MemoChecklist
  INTERACTIVE_ATTR = /\A\[%interactive\]\s*\z/
  CHECKLIST_ITEM = /\A(\s*)\* \[([ Xx])\] (.+)\z/
  ID_SUFFIX = /\s+#([\w][\w-]*)\z/

  class Error < StandardError; end

  ChecklistItem = Data.define(:line_index, :indent, :checked, :label, :id)

  def self.sync_properties_from_body!(memo)
    new(memo).sync_properties_from_body!
  end

  def self.toggle!(memo, id:, checked:)
    new(memo).toggle!(id: id, checked: checked)
  end

  def self.interactive_items(memo)
    new(memo).send(:parse_interactive_items)
  end

  def initialize(memo)
    @memo = memo
    @lines = memo.body.to_s.split("\n", -1)
  end

  def sync_properties_from_body!
    items = parse_interactive_items
    return clear_checkboxes! if items.empty?

    existing = Array(@memo.properties["checkboxes"])
    by_id = existing.index_by { |row| row["id"].to_s }
    used_ids = Set.new

    rows = items.map.with_index do |item, index|
      id = resolve_id(item, index, by_id, used_ids)
      used_ids << id
      {
        "id" => id,
        "label" => item.label,
        "checked" => item.checked
      }
    end

    @memo.properties = @memo.properties.merge("checkboxes" => rows)
    inject_missing_ids!(items, rows)
    @memo.body = @lines.join("\n")
    rows
  end

  def toggle!(id:, checked:)
    id = id.to_s
    raise Error, "チェックリスト id が空です" if id.blank?

    sync_properties_from_body! unless body_ids_match_properties?

    item = parse_interactive_items.find { |entry| entry.id == id }
    raise Error, "チェックリスト id が見つかりません: #{id}" unless item

    marker = checked ? "x" : " "
    line = @lines[item.line_index]
    @lines[item.line_index] = line.sub(CHECKLIST_ITEM) do
      indent = Regexp.last_match(1)
      label = Regexp.last_match(3).sub(ID_SUFFIX, "").strip
      "#{indent}* [#{marker}] #{label} ##{id}"
    end
    @memo.body = @lines.join("\n")
    sync_properties_from_body!
  end

  private

  def clear_checkboxes!
    props = @memo.properties.except("checkboxes")
    @memo.properties = props
  end

  def body_ids_match_properties?
    items = parse_interactive_items
    return true if items.empty?

    props = Array(@memo.properties["checkboxes"])
    items.size == props.size && items.all?(&:id) && items.map(&:id) == props.map { |r| r["id"].to_s }
  end

  def parse_interactive_items
    items = []
    interactive = false

    @lines.each_with_index do |line, line_index|
      stripped = line.strip

      if INTERACTIVE_ATTR.match?(stripped)
        interactive = true
        next
      end

      match = CHECKLIST_ITEM.match(line)
      if interactive && match
        checked = match[2] != " "
        rest = match[3]
        id_match = rest.match(ID_SUFFIX)
        id = id_match ? id_match[1] : nil
        label = id_match ? rest.sub(ID_SUFFIX, "").strip : rest.strip
        items << ChecklistItem.new(
          line_index: line_index,
          indent: match[1],
          checked: checked,
          label: label,
          id: id
        )
        next
      end

      interactive = false if interactive && stripped.present? && !match
    end

    items
  end

  def resolve_id(item, index, by_id, used_ids)
    return item.id if item.id.present? && !used_ids.include?(item.id)

    by_label = by_id.values.find { |row| row["label"].to_s == item.label }
    return by_label["id"].to_s if by_label && !used_ids.include?(by_label["id"].to_s)

    candidate = item.id.presence || "cb-#{index + 1}"
    candidate = next_free_id(candidate, used_ids)
    candidate
  end

  def next_free_id(base, used_ids)
    return base unless used_ids.include?(base)

    n = 2
    loop do
      candidate = "#{base}-#{n}"
      return candidate unless used_ids.include?(candidate)
      n += 1
    end
  end

  def inject_missing_ids!(items, rows)
    items.each_with_index do |item, index|
      row = rows[index]
      next if item.id == row["id"]

      line = @lines[item.line_index]
      @lines[item.line_index] = line.sub(ID_SUFFIX, "").rstrip + " ##{row["id"]}"
    end
  end
end
