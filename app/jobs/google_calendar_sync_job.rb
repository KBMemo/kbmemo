# frozen_string_literal: true

class GoogleCalendarSyncJob < ApplicationJob
  queue_as :kbmemo_site

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account&.google_calendar_connected?

    result = GoogleCalendar::Sync.call(account: account)
    return if result.errors.empty?

    Rails.logger.warn("[GoogleCalendarSyncJob] account=#{account_id} #{result.errors.join('; ')}")
  end
end
