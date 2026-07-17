# frozen_string_literal: true

require "test_helper"

module NyoyMemoWebhook
  class ClientTest < ActiveSupport::TestCase
    test "configured only when enabled url and secret are present" do
      assert Client.new(url: "http://nyoy.test/webhooks/kbmemo/memos", secret: "s", enabled: "true").configured?
      assert_not Client.new(url: "http://nyoy.test/webhooks/kbmemo/memos", secret: "s", enabled: "false").configured?
      assert_not Client.new(url: "", secret: "s", enabled: "true").configured?
      assert_not Client.new(url: "http://nyoy.test/webhooks/kbmemo/memos", secret: "", enabled: "true").configured?
    end

    test "post sends signed json payload" do
      captured = {}
      response = Object.new
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }

      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:request] = request
        response
      end

      Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
        client = Client.new(url: "http://nyoy.test/webhooks/kbmemo/memos", secret: "secret", enabled: "true")
        assert client.post!(event_id: "evt-1", event_type: "memo.updated")
      end

      request = captured.fetch(:request)
      timestamp = request["X-KBMemo-Webhook-Timestamp"]
      assert_equal "application/json", request["Content-Type"]
      assert_equal "application/json", request["Accept"]
      assert_equal(
        Signature.sign(raw_body: request.body, timestamp: timestamp, secret: "secret"),
        request["X-KBMemo-Signature"]
      )
      assert_equal "evt-1", JSON.parse(request.body).fetch("event_id")
    end

    test "post raises when response is not success" do
      response = Object.new
      response.define_singleton_method(:is_a?) { |_klass| false }
      response.define_singleton_method(:code) { "500" }

      http = Object.new
      http.define_singleton_method(:request) { |_request| response }

      Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
        client = Client.new(url: "http://nyoy.test/webhooks/kbmemo/memos", secret: "secret", enabled: "true")
        error = assert_raises(Client::Error) { client.post!(event_id: "evt-1") }
        assert_includes error.message, "HTTP 500"
      end
    end
  end
end
