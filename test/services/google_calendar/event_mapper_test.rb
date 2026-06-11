# frozen_string_literal: true

require "test_helper"
require "google/apis/calendar_v3"

class GoogleCalendar::EventMapperTest < ActiveSupport::TestCase
  test "maps event to memo fields" do
    event = Google::Apis::CalendarV3::Event.new(
      id: "evt1",
      summary: "Standup",
      description: "Daily sync",
      location: "Room A",
      html_link: "https://calendar.google.com/event?eid=1",
      etag: "etag-1",
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: Time.zone.parse("2026-06-01 10:00:00")
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: Time.zone.parse("2026-06-01 11:00:00")
      )
    )

    memo = Memo.new(properties: {})
    GoogleCalendar::EventMapper.apply!(memo: memo, event: event, calendar_id: "primary")

    assert_equal "Standup", memo.title
    assert_equal Date.new(2026, 6, 1), memo.scheduled_on
    assert_includes memo.body, "Daily sync"
    assert_includes memo.body, "Room A"
    assert_equal "evt1", memo.properties.dig("google_calendar", "event_id")
    assert_equal true, memo.properties.dig("google_calendar", "read_only")
  end

  test "maps all-day event scheduled_on from date" do
    event = Google::Apis::CalendarV3::Event.new(
      id: "allday",
      summary: "Holiday",
      start: Google::Apis::CalendarV3::EventDateTime.new(date: "2026-06-02"),
      end: Google::Apis::CalendarV3::EventDateTime.new(date: "2026-06-03")
    )

    memo = Memo.new(properties: {})
    GoogleCalendar::EventMapper.apply!(memo: memo, event: event, calendar_id: "primary")

    assert_equal Date.new(2026, 6, 2), memo.scheduled_on
    assert_equal true, memo.properties.dig("google_calendar", "all_day")
  end

  test "maps recurring event recurrence lines" do
    event = Google::Apis::CalendarV3::Event.new(
      id: "weekly",
      summary: "Weekly sync",
      recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=WE" ],
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: Time.zone.parse("2026-06-03 10:00:00")
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: Time.zone.parse("2026-06-03 11:00:00")
      )
    )

    memo = Memo.new(properties: {})
    GoogleCalendar::EventMapper.apply!(memo: memo, event: event, calendar_id: "primary")

    assert_equal [ "RRULE:FREQ=WEEKLY;BYDAY=WE" ], memo.properties.dig("google_calendar", "recurrence")
    assert_equal true, memo.properties.dig("google_calendar", "recurring")
  end
end
