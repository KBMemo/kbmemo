# frozen_string_literal: true

require "googleauth"

module GoogleCalendar
  class OAuth
    AUTH_URI = "https://accounts.google.com/o/oauth2/auth"
    TOKEN_URI = "https://oauth2.googleapis.com/token"

    def self.authorization_url(state:, redirect_uri:)
      new.authorization_url(state: state, redirect_uri: redirect_uri)
    end

    def self.exchange_code!(code:, redirect_uri:)
      new.exchange_code!(code: code, redirect_uri: redirect_uri)
    end

    def authorization_url(state:, redirect_uri:)
      client = signet_client(redirect_uri: redirect_uri)
      client.state = state
      client.authorization_uri(
        access_type: "offline",
        prompt: "consent",
        include_granted_scopes: true
      ).to_s
    end

    def exchange_code!(code:, redirect_uri:)
      client = signet_client(redirect_uri: redirect_uri)
      client.code = code
      client.fetch_access_token!
      client
    end

    private

    def signet_client(redirect_uri:)
      Signet::OAuth2::Client.new(
        client_id: Credentials.client_id,
        client_secret: Credentials.client_secret,
        authorization_uri: AUTH_URI,
        token_credential_uri: TOKEN_URI,
        redirect_uri: redirect_uri,
        scope: Credentials.scope
      )
    end
  end
end
