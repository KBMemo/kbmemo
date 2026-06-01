# frozen_string_literal: true

require "test_helper"

class GoogleCalendar::ClearTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @account.connect_google_calendar!(refresh_token: "refresh-test")
    @account.update!(google_calendar_meta: @account.google_calendar_meta.merge("sync_token" => "token-1"))
  end

  test "deletes synced memos and clears sync token" do
    memo = Memo.create!(
      account: @account,
      memo_directory: memo_directories(:work),
      title: "GCal event",
      body: "",
      properties: {
        "scheduled_on" => "2026-06-01",
        "google_calendar" => {
          "event_id" => "evt-clear",
          "calendar_id" => "primary",
          "read_only" => true
        }
      }
    )

    result = GoogleCalendar::Clear.call(account: @account)

    assert result.success?
    assert_equal 1, result.deleted_count
    assert_not Memo.exists?(memo.id)
    assert_nil @account.reload.google_calendar_sync_token
    assert @account.google_calendar_connected?
  end

  test "leaves non-google-calendar memos intact" do
    memo = memos(:one)

    result = GoogleCalendar::Clear.call(account: @account)

    assert result.success?
    assert_equal 0, result.deleted_count
    assert Memo.exists?(memo.id)
  end
end
