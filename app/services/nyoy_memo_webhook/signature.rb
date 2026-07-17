# frozen_string_literal: true

module NyoyMemoWebhook
  class Signature
    ALGORITHM = "sha256"

    def self.sign(raw_body:, timestamp:, secret:)
      digest = OpenSSL::HMAC.hexdigest(
        ALGORITHM,
        secret.to_s,
        "#{timestamp}.#{raw_body}"
      )
      "#{ALGORITHM}=#{digest}"
    end
  end
end
