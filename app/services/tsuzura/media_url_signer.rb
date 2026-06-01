# frozen_string_literal: true

module Tsuzura
  class MediaUrlSigner
    class << self
      def secret
        ENV["TSUZURA_URL_SIGNING_SECRET"].presence ||
          Rails.application.credentials.dig(:tsuzura, :url_signing_secret).presence ||
          Rails.application.secret_key_base
      end

      def base_url
        ENV.fetch("TSUZURA_PUBLIC_URL", "http://localhost:3008")
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
