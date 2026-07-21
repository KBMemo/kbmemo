# frozen_string_literal: true

require "test_helper"

class QueueIsolationTest < ActiveSupport::TestCase
  test "site jobs use the site-only queue" do
    job_classes = [
      GoogleCalendarSyncJob,
      MemoEmbeddingIndexJob,
      NyoyMemoWebhookJob
    ]

    assert_equal [ "kbmemo_site" ], job_classes.map(&:queue_name).uniq
  end
end
