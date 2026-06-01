# frozen_string_literal: true

module GoogleCalendar
  class EventMapper
    TAG = "google-calendar"
    PROPERTIES_KEY = "google_calendar"

    class << self
      def apply!(memo:, event:, calendar_id:)
        memo.title = event.summary.presence || "（タイトルなし）"
        memo.title_manual = true
        memo.body = build_body(event)
        memo.scheduled_on = parse_scheduled_on(event)
        existing = memo.properties.dig(PROPERTIES_KEY) || {}
        payload = properties_payload(event, calendar_id)
        payload["cancelled_occurrences"] = existing["cancelled_occurrences"] if existing["cancelled_occurrences"].present?
        memo.properties = memo.properties.merge(PROPERTIES_KEY => payload)
        memo
      end

      def properties_payload(event, calendar_id)
        {
          "calendar_id" => calendar_id,
          "event_id" => event.id,
          "etag" => event.etag,
          "html_link" => event.html_link,
          "starts_at" => iso_timestamp(event.start),
          "ends_at" => iso_timestamp(event.end),
          "all_day" => all_day?(event),
          "location" => event.location.presence,
          "recurrence" => recurrence_lines(event),
          "recurring" => recurrence_lines(event).present?,
          "synced_at" => Time.current.iso8601,
          "read_only" => true
        }.compact
      end

      def occurrence_date(event)
        point = event.original_start_time || event.start
        return nil unless point

        if point.date
          coerce_date(point.date)
        elsif point.date_time
          point.date_time.in_time_zone.to_date
        end
      end

      def build_body(event)
        parts = []
        if event.location.present?
          parts << "場所: #{event.location}"
          parts << ""
        end
        if event.description.present?
          parts << event.description.strip
          parts << ""
        end
        if event.html_link.present?
          parts << "Google Calendar: #{event.html_link}"
        end
        parts.join("\n").strip
      end

      def parse_scheduled_on(event)
        if event.start&.date
          coerce_date(event.start.date)
        elsif event.start&.date_time
          event.start.date_time.in_time_zone.to_date
        end
      end

      def coerce_date(value)
        return value if value.is_a?(Date)

        Date.iso8601(value.to_s)
      end

      def all_day?(event)
        event.start&.date.present?
      end

      def iso_timestamp(point)
        return nil unless point

        if point.date
          coerce_date(point.date).iso8601
        elsif point.date_time
          point.date_time.in_time_zone.iso8601
        end
      end

      def recurrence_lines(event)
        Array(event.recurrence).map(&:to_s).reject(&:blank?)
      end
    end
  end
end
