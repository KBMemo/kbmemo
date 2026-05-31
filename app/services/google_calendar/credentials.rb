# frozen_string_literal: true

module GoogleCalendar
  module Credentials
    module_function

    def scope
      require "google/apis/calendar_v3"
      Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY
    end

    def configured?
      client_id.present? && client_secret.present?
    end

    def valid?
      return false unless configured?
      return false if placeholder?

      client_id.match?(CLIENT_ID_FORMAT)
    end

    def misconfiguration_reason
      return "client_id / client_secret が未設定です" unless configured?
      return "credentials がテンプレートのままです（google_calendar.example.yml を参照）" if placeholder?
      return "client_id の形式が不正です（*.apps.googleusercontent.com）" unless client_id.match?(CLIENT_ID_FORMAT)

      nil
    end

    CLIENT_ID_FORMAT = /\A[\w-]+\.apps\.googleusercontent\.com\z/

    def client_id
      fetch(:client_id)
    end

    def client_secret
      fetch(:client_secret)
    end

    def fetch(key)
      env_key = ENV["GOOGLE_CALENDAR_#{key.to_s.upcase}"]
      return env_key if env_key.present?

      Rails.application.credentials.dig(:google_calendar, key.to_sym).presence ||
        Rails.application.credentials.dig(:google_calendar, key.to_s).presence
    end

    def placeholder?
      combined = [ client_id, client_secret ].join(" ")
      combined.match?(/your[-_\s]?client|your_development|example\.com|placeholder/i)
    end
    private_class_method :fetch, :placeholder?
  end
end
