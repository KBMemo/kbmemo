# frozen_string_literal: true

module AccountGoogleCalendar
  extend ActiveSupport::Concern

  included do
    encrypts :google_calendar_refresh_token
  end

  def google_calendar_connected?
    encrypted_attribute_decryptable?(:google_calendar_refresh_token)
  end

  def google_calendar_refresh_token_undecryptable?
    encrypted_ciphertext_present?(:google_calendar_refresh_token) &&
      !encrypted_attribute_decryptable?(:google_calendar_refresh_token)
  end

  def google_calendar_meta
    raw = super
    raw.is_a?(Hash) ? raw.stringify_keys : {}
  end

  def google_calendar_sync_token
    google_calendar_meta["sync_token"].presence
  end

  def clear_google_calendar_sync_token!
    meta = google_calendar_meta.dup
    meta.delete("sync_token")
    update!(google_calendar_meta: meta)
  end

  def connect_google_calendar!(refresh_token:)
    meta = google_calendar_meta.merge(
      "calendar_id" => google_calendar_meta["calendar_id"].presence || "primary",
      "connected_at" => Time.current.iso8601
    )
    update!(
      google_calendar_refresh_token: refresh_token,
      google_calendar_meta: meta
    )
  end

  def disconnect_google_calendar!
    update!(
      google_calendar_refresh_token: nil,
      google_calendar_meta: {}
    )
  end
end
