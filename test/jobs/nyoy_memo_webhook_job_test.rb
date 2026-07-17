# frozen_string_literal: true

require "test_helper"

class NyoyMemoWebhookJobTest < ActiveJob::TestCase
  test "posts normalized webhook payload" do
    delivered = nil
    client = Object.new
    client.define_singleton_method(:post!) { |payload| delivered = payload }

    NyoyMemoWebhook::Client.stub(:new, client) do
      NyoyMemoWebhookJob.perform_now(
        event_id: "evt-1",
        event_type: "memo.updated",
        account_id: 1,
        memo_uid: "01KDWPVNG07BG517AZGRFTG06Z",
        memo_id: 123,
        memo_updated_at: Time.utc(2026, 7, 17, 1, 2, 3),
        occurred_at: Time.utc(2026, 7, 17, 1, 2, 4)
      )
    end

    assert_equal "evt-1", delivered.fetch(:event_id)
    assert_equal "memo.updated", delivered.fetch(:event_type)
    assert_equal 1, delivered.fetch(:account_id)
    assert_equal "01KDWPVNG07BG517AZGRFTG06Z", delivered.fetch(:memo_uid)
    assert_equal 123, delivered.fetch(:memo_id)
    assert_equal "2026-07-17T01:02:03.000000Z", delivered.fetch(:memo_updated_at)
    assert_equal "2026-07-17T01:02:04.000000Z", delivered.fetch(:occurred_at)
  end
end
