# frozen_string_literal: true

class NyoyMemoWebhookJob < ApplicationJob
  queue_as :kbmemo_site

  def perform(event_type:, account_id:, memo_uid:, memo_id: nil, memo_updated_at: nil, occurred_at: nil, event_id: nil)
    payload = {
      event_id: event_id.presence || SecureRandom.uuid,
      event_type: event_type,
      account_id: account_id,
      memo_uid: memo_uid,
      memo_id: memo_id,
      memo_updated_at: memo_updated_at&.iso8601(6),
      occurred_at: (occurred_at || Time.current).iso8601(6)
    }.compact

    NyoyMemoWebhook::Client.new.post!(payload)
  end
end
