# frozen_string_literal: true

require "test_helper"

module Chat
  class PromptsTest < ActiveSupport::TestCase
    test "role default prompts" do
      assert_equal Chat::Prompts::FAST_CHAT, Chat::Prompts.system_for(role: :fast_chat)
      assert_equal Chat::Prompts::MAIN, Chat::Prompts.system_for(role: :main)
      assert_equal Chat::Prompts::VISION, Chat::Prompts.system_for(role: :vision)
    end

    test "code intent overrides role default with CODING prompt" do
      assert_equal Chat::Prompts::CODING, Chat::Prompts.system_for(role: :main, intent: "code")
    end

    test "tool-dependent prompts are not auto-injected before their phase" do
      # rag_lookup / image_analysis はツール未実装の間は役割別の既定に留める。
      assert_equal Chat::Prompts::MAIN, Chat::Prompts.system_for(role: :main, intent: "rag_lookup")
      assert_equal Chat::Prompts::MAIN, Chat::Prompts.system_for(role: :main, intent: "image_analysis")
    end

    test "unknown role without intent returns nil" do
      assert_nil Chat::Prompts.system_for(role: :image_generation)
      assert_nil Chat::Prompts.system_for(role: nil)
    end

    test "intent classifier reuses the centralized prompt" do
      assert_equal Chat::Prompts::INTENT_CLASSIFIER, Chat::IntentClassifier::SYSTEM_PROMPT
    end
  end
end
