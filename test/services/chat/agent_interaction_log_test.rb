# frozen_string_literal: true

require "test_helper"

class Chat::AgentInteractionLogTest < ActiveSupport::TestCase
  test "appends and merges streaming chunks" do
    log = Chat::AgentInteractionLog.new
    log.record(step_key: :generate, role: "response", model: "gemma", text: "Hel", append: true)
    log.record(step_key: :generate, role: "response", model: "gemma", text: "lo", append: true)

    json = log.as_json
    assert_equal 1, json.size
    assert_equal "Hello", json.first["text"]
  end
end
