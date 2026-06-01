# frozen_string_literal: true

module GoogleCalendar
  # single_events: false 時に返る繰り返しインスタンス（取消・例外）をマスターメモへ反映する。
  class RecurringExceptions
    class << self
      def apply!(memo:, event:)
        date = EventMapper.occurrence_date(event)
        return memo unless date

        gcal = memo.properties.fetch(EventMapper::PROPERTIES_KEY, {}).stringify_keys
        cancelled = Array(gcal["cancelled_occurrences"])

        if event.status == "cancelled"
          iso = date.iso8601
          gcal["cancelled_occurrences"] = (cancelled + [ iso ]).uniq.sort unless cancelled.include?(iso)
        end

        memo.properties = memo.properties.merge(EventMapper::PROPERTIES_KEY => gcal)
        memo
      end

      def exception_unchanged?(memo, event)
        date = EventMapper.occurrence_date(event)
        return true unless date

        cancelled = Array(memo.properties.dig(EventMapper::PROPERTIES_KEY, "cancelled_occurrences"))
        event.status == "cancelled" && cancelled.include?(date.iso8601)
      end
    end
  end
end
