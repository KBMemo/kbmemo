# frozen_string_literal: true

require "test_helper"

module Chat
  class RouterTest < ActiveSupport::TestCase
    def intent(name, confidence: 0.9)
      Chat::IntentClassifier::Result.new(
        intent: name, confidence: confidence, needs_tool: false, reason: ""
      )
    end

    test "conversation routes to fast_chat without tools" do
      decision = Chat::Router.decide(intent("conversation"))
      assert_equal :fast_chat, decision.model_role
      assert_empty decision.tools
    end

    test "code routes to main" do
      assert_equal :main, Chat::Router.decide(intent("code")).model_role
    end

    test "url_analysis carries fetch_url tool" do
      decision = Chat::Router.decide(intent("url_analysis"))
      assert_equal :fast_chat, decision.model_role
      assert_includes decision.tools, :fetch_url
    end

    test "image_generation routes to image_generation role" do
      assert_equal :image_generation, Chat::Router.decide(intent("image_generation")).model_role
    end

    test "unknown intent uses default fast_chat route" do
      assert_equal :fast_chat, Chat::Router.decide(intent("unknown")).model_role
    end
  end
end
