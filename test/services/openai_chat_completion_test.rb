# frozen_string_literal: true

require "test_helper"

class OpenaiChatCompletionTest < ActiveSupport::TestCase
  test "call returns assistant content on success" do
    response_body = {
      "choices" => [
        { "message" => { "role" => "assistant", "content" => "== Title\n\nBody" } }
      ]
    }

    client = OpenaiChatCompletion.new(api_key: "sk-test")
    client.define_singleton_method(:http_post) { |_payload| response_body }

    assert_equal "== Title\n\nBody", client.call([ { role: "user", content: "hi" } ])
  end

  test "call raises when api key blank" do
    client = OpenaiChatCompletion.new(api_key: "")
    assert_raises(OpenaiChatCompletion::Error) do
      client.call([ { role: "user", content: "hi" } ])
    end
  end
end
