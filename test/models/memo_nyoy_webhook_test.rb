# frozen_string_literal: true

require "test_helper"

class MemoNyoyWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_enabled = ENV["NYOY_MEMO_WEBHOOK_ENABLED"]
    @original_url = ENV["NYOY_MEMO_WEBHOOK_URL"]
    @original_secret = ENV["NYOY_MEMO_WEBHOOK_SECRET"]
    ENV["NYOY_MEMO_WEBHOOK_ENABLED"] = "true"
    ENV["NYOY_MEMO_WEBHOOK_URL"] = "http://nyoy.test/webhooks/kbmemo/memos"
    ENV["NYOY_MEMO_WEBHOOK_SECRET"] = "secret"
    clear_enqueued_jobs
  end

  teardown do
    ENV["NYOY_MEMO_WEBHOOK_ENABLED"] = @original_enabled
    ENV["NYOY_MEMO_WEBHOOK_URL"] = @original_url
    ENV["NYOY_MEMO_WEBHOOK_SECRET"] = @original_secret
    clear_enqueued_jobs
  end

  test "committed memo body update enqueues update webhook" do
    memo = memos(:one)

    assert_enqueued_with(job: NyoyMemoWebhookJob) do
      memo.update!(body: "= Updated")
    end

    job = enqueued_jobs.last
    assert_equal "memo.updated", job.dig(:args, 0, "event_type")
    assert_equal memo.uid, job.dig(:args, 0, "memo_uid")
  end

  test "draft memo update does not enqueue webhook" do
    memo = memos(:one)
    memo.update_column(:file_committed_at, nil)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: NyoyMemoWebhookJob) do
      memo.update!(body: "= Draft")
    end
  end

  test "memo destroy enqueues delete webhook" do
    memo = memos(:one)

    assert_enqueued_with(job: NyoyMemoWebhookJob) do
      memo.destroy!
    end

    job = enqueued_jobs.last
    assert_equal "memo.deleted", job.dig(:args, 0, "event_type")
    assert_equal memo.uid, job.dig(:args, 0, "memo_uid")
  end

  test "unconfigured webhook does not enqueue" do
    ENV["NYOY_MEMO_WEBHOOK_ENABLED"] = "false"

    assert_no_enqueued_jobs(only: NyoyMemoWebhookJob) do
      memos(:one).update!(body: "= No webhook")
    end
  end
end
