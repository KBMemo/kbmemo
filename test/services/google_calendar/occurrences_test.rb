# frozen_string_literal: true

require "test_helper"

class GoogleCalendar::OccurrencesTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
  end

  test "expands weekly recurrence across range" do
    memo = build_recurring_memo(
      starts_at: "2026-06-03T10:00:00+09:00",
      recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=WE" ]
    )

    dates = GoogleCalendar::Occurrences.dates_in_range(memo, Date.new(2026, 6, 1)..Date.new(2026, 6, 30))

    assert_equal [ Date.new(2026, 6, 3), Date.new(2026, 6, 10), Date.new(2026, 6, 17), Date.new(2026, 6, 24) ], dates
  end

  test "excludes cancelled occurrence dates" do
    memo = build_recurring_memo(
      starts_at: "2026-06-03T10:00:00+09:00",
      recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=WE" ],
      cancelled_occurrences: [ "2026-06-10" ]
    )

    dates = GoogleCalendar::Occurrences.dates_in_range(memo, Date.new(2026, 6, 1)..Date.new(2026, 6, 30))

    assert_includes dates, Date.new(2026, 6, 3)
    assert_not_includes dates, Date.new(2026, 6, 10)
  end

  test "single event uses scheduled_on only" do
    memo = Memo.new(
      properties: {
        "scheduled_on" => "2026-06-01",
        "google_calendar" => { "event_id" => "evt-1", "starts_at" => "2026-06-01T10:00:00+09:00" }
      }
    )

    assert_equal [ Date.new(2026, 6, 1) ], GoogleCalendar::Occurrences.dates_in_range(memo, Date.new(2026, 6, 1)..Date.new(2026, 6, 7))
  end

  private

  def build_recurring_memo(starts_at:, recurrence:, cancelled_occurrences: nil)
    gcal = {
      "event_id" => "evt-recur",
      "starts_at" => starts_at,
      "recurrence" => recurrence,
      "recurring" => true,
      "all_day" => false
    }
    gcal["cancelled_occurrences"] = cancelled_occurrences if cancelled_occurrences
    Memo.new(
      properties: {
        "scheduled_on" => Time.zone.parse(starts_at).to_date.iso8601,
        "google_calendar" => gcal
      }
    )
  end
end
