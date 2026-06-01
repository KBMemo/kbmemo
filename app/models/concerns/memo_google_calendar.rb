# frozen_string_literal: true

module MemoGoogleCalendar
  extend ActiveSupport::Concern

  GOOGLE_CALENDAR_KEY = "google_calendar"

  def google_calendar_synced?
    properties.is_a?(Hash) && properties.dig(GOOGLE_CALENDAR_KEY, "event_id").present?
  end

  def google_calendar_read_only?
    google_calendar_synced? && properties.dig(GOOGLE_CALENDAR_KEY, "read_only") != false
  end

  def google_calendar_html_link
    properties.dig(GOOGLE_CALENDAR_KEY, "html_link")
  end

  def google_calendar_recurring?
    google_calendar_synced? && (
      properties.dig(GOOGLE_CALENDAR_KEY, "recurring") == true ||
      Array(properties.dig(GOOGLE_CALENDAR_KEY, "recurrence")).grep(/\ARRRULE:/).any?
    )
  end

  def sync_read_only?
    docs_sync_read_only? || google_calendar_read_only?
  end
end
