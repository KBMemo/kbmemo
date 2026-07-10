# frozen_string_literal: true

require "test_helper"

class Chat::AgentTraceTest < ActiveSupport::TestCase
  test "records step elapsed time and stats" do
    trace = Chat::AgentTrace.new

    trace.run(:intent, "Intent 分類") do
      trace.finish_step_detail("conversation (90%)")
      :ok
    end

    json = trace.as_json(account: accounts(:one), intent: "conversation", model_role: :fast_chat)

    assert_equal 1, json["steps"].size
    assert_equal "Intent 分類", json["steps"].first["label"]
    assert_equal "completed", json["steps"].first["status"]
    assert_not_nil json["steps"].first["elapsed_ms"]
    assert_operator json["steps"].first["elapsed_ms"], :>=, 0
    assert_includes json["stats"].map { |s| s["label"] }, "モデル"
    assert_includes json["stats"].map { |s| s["label"] }, "経過"
  end
end
