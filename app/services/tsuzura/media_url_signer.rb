# frozen_string_literal: true

module Tsuzura
  class MediaUrlSigner
    PRODUCTION_DEFAULT_PUBLIC_URL = "https://media.kbmemo.net"
    # 開発時に localhost へ署名した image:: を本番 URL へ差し替える（DB 本文は変更しない）。
    LEGACY_SIGNED_IMAGE = %r{
      image::https?://[^/\s\[]+
      /v1/media/([0-9A-HJKMNP-TV-Z]{26})/web\?
      [^\s\[]*
      (\[[^\]]*\])?
    }ix

    class << self
      def secret
        ENV["TSUZURA_URL_SIGNING_SECRET"].presence ||
          Rails.application.credentials.dig(:tsuzura, :url_signing_secret).presence ||
          Rails.application.secret_key_base
      end

      def base_url
        Endpoints.public_url
      end

      def sign(media_id:, memo_id:, exp: 1.hour.from_now)
        exp_i = exp.to_i
        sig = signature(media_id:, memo_id:, exp: exp_i)
        "#{base_url}/v1/media/#{media_id}/web?memo_id=#{memo_id}&exp=#{exp_i}&sig=#{sig}"
      end

      def signature(media_id:, memo_id:, exp:)
        payload = "#{media_id}:#{memo_id}:#{exp}"
        OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      end
    end
  end
end
