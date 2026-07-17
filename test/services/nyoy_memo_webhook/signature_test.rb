# frozen_string_literal: true

require "test_helper"

module NyoyMemoWebhook
  class SignatureTest < ActiveSupport::TestCase
    test "signs timestamp and raw body with hmac sha256" do
      signature = Signature.sign(raw_body: '{"ok":true}', timestamp: "123", secret: "secret")
      digest = OpenSSL::HMAC.hexdigest("sha256", "secret", '123.{"ok":true}')

      assert_equal "sha256=#{digest}", signature
    end
  end
end
