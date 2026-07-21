# frozen_string_literal: true

require "test_helper"
require "google/apis/calendar_v3"

class GoogleCalendar::SyncTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @account.connect_google_calendar!(refresh_token: "refresh-test")
    Memo.where(account_id: @account.id).where(
      "#{MemoPropertiesSql.json_text_at('google_calendar', 'event_id')} IS NOT NULL"
    ).delete_all
  end

  test "creates memo for new event" do
    event = build_event(id: "evt-new", summary: "New meeting", etag: "e1")
    client = fake_client([ event ])

    with_credentials do
      result = GoogleCalendar::Sync.call(account: @account, client: client)
      assert_equal 1, result.created
    end

    memo = find_memo("evt-new")
    assert_equal "New meeting", memo.title
    assert_equal Date.new(2026, 6, 1), memo.scheduled_on
    assert memo.tags.map(&:name).include?("google-calendar")
    assert memo.google_calendar_read_only?
  end

  test "skips unchanged event" do
    event = build_event(id: "evt-skip", summary: "Same", etag: "same")
    client = fake_client([ event ])

    with_credentials do
      GoogleCalendar::Sync.call(account: @account, client: client)
      result = GoogleCalendar::Sync.call(account: @account, client: client)
      assert_equal 1, result.skipped
      assert_equal 0, result.updated
    end
  end

  test "deletes memo for cancelled event" do
    event = build_event(id: "evt-del", summary: "Gone", etag: "e1")
    client = fake_client([ event ])

    with_credentials do
      GoogleCalendar::Sync.call(account: @account, client: client)
    end

    cancelled = build_event(id: "evt-del", status: "cancelled", etag: "e2")
    client = fake_client([ cancelled ])

    with_credentials do
      result = GoogleCalendar::Sync.call(account: @account, client: client)
      assert_equal 1, result.deleted
    end

    assert_nil find_memo("evt-del")
  end

  test "creates one memo for recurring master event" do
    event = build_event(
      id: "evt-weekly",
      summary: "Weekly",
      etag: "e1",
      start: Google::Apis::CalendarV3::EventDateTime.new(date_time: Time.zone.parse("2026-06-03 10:00:00")),
      ends: Google::Apis::CalendarV3::EventDateTime.new(date_time: Time.zone.parse("2026-06-03 11:00:00")),
      recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=WE" ]
    )
    client = fake_client([ event ])

    with_credentials do
      result = GoogleCalendar::Sync.call(account: @account, client: client)
      assert_equal 1, result.created
    end

    memo = find_memo("evt-weekly")
    assert memo.google_calendar_recurring?
    assert_equal [ "RRULE:FREQ=WEEKLY;BYDAY=WE" ], memo.properties.dig("google_calendar", "recurrence")
  end

  test "records cancelled recurring occurrence on master memo" do
    master = build_event(
      id: "evt-weekly",
      summary: "Weekly",
      etag: "e1",
      start: Google::Apis::CalendarV3::EventDateTime.new(date_time: Time.zone.parse("2026-06-03 10:00:00")),
      ends: Google::Apis::CalendarV3::EventDateTime.new(date_time: Time.zone.parse("2026-06-03 11:00:00")),
      recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=WE" ]
    )
    with_credentials { GoogleCalendar::Sync.call(account: @account, client: fake_client([ master ])) }

    cancelled = Google::Apis::CalendarV3::Event.new(
      id: "evt-weekly_20260610",
      recurring_event_id: "evt-weekly",
      status: "cancelled",
      etag: "e2",
      original_start_time: Google::Apis::CalendarV3::EventDateTime.new(date_time: Time.zone.parse("2026-06-10 10:00:00"))
    )

    with_credentials do
      result = GoogleCalendar::Sync.call(account: @account, client: fake_client([ cancelled ]))
      assert_equal 1, result.updated
    end

    memo = find_memo("evt-weekly")
    assert_includes memo.properties.dig("google_calendar", "cancelled_occurrences"), "2026-06-10"
  end

  private

  def build_event(id:, summary: "Event", etag: "etag", status: "confirmed", start: nil, ends: nil, recurrence: nil)
    Google::Apis::CalendarV3::Event.new(
      id: id,
      summary: summary,
      status: status,
      etag: etag,
      html_link: "https://calendar.google.com/event?eid=#{id}",
      start: start || Google::Apis::CalendarV3::EventDateTime.new(date: "2026-06-01"),
      end: ends || Google::Apis::CalendarV3::EventDateTime.new(date: "2026-06-02"),
      recurrence: recurrence
    )
  end

  def fake_client(events)
    Class.new do
      define_method(:initialize) { |items| @items = items }
      define_method(:list_events) do |**|
        Google::Apis::CalendarV3::Events.new(items: @items, next_sync_token: "next-token")
      end
    end.new(events)
  end

  def find_memo(event_id)
    path = MemoPropertiesSql.json_text_at("google_calendar", "event_id")
    Memo.where(account_id: @account.id).find_by("#{path} = ?", event_id)
  end

  def with_credentials
    original = GoogleCalendar::Credentials.method(:configured?)
    GoogleCalendar::Credentials.define_singleton_method(:configured?) { true }
    yield
  ensure
    GoogleCalendar::Credentials.define_singleton_method(:configured?, original)
  end
end
