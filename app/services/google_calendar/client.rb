# frozen_string_literal: true

require "google/apis/calendar_v3"

module GoogleCalendar
  class Client
    class Error < StandardError; end
    class SyncTokenExpired < Error; end

    CalendarService = Google::Apis::CalendarV3::CalendarService

    def initialize(account:)
      @account = account
    end

    def list_events(calendar_id:, sync_token: nil, time_min: nil, time_max: nil, page_token: nil)
      service = calendar_service
      service.list_events(
        calendar_id,
        sync_token: sync_token,
        time_min: time_min&.utc&.iso8601,
        time_max: time_max&.utc&.iso8601,
        single_events: true,
        show_deleted: true,
        max_results: 250,
        page_token: page_token
      )
    rescue Google::Apis::ClientError => e
      raise SyncTokenExpired, e.message if e.status_code == 410

      raise Error, e.message
    end

    private

    def calendar_service
      CalendarService.new.tap do |service|
        service.authorization = authorization
      end
    end

    def authorization
      creds = Google::Auth::UserRefreshCredentials.new(
        client_id: Credentials.client_id,
        client_secret: Credentials.client_secret,
        scope: Credentials.scope,
        refresh_token: @account.google_calendar_refresh_token
      )
      creds.fetch_access_token!
      creds
    end
  end
end
