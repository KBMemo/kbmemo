# frozen_string_literal: true

require "test_helper"

module Chat
  class EscalationTest < ActiveSupport::TestCase
    def intent(name, confidence: 0.9)
      Chat::IntentClassifier::Result.new(
        intent: name, confidence: confidence, needs_tool: false, reason: ""
      )
    end

    test "never escalates when already on main" do
      refute Chat::Escalation.escalate?(
        intent: intent("code", confidence: 0.1), user_text: "実装して", model_role: :main
      )
    end

    test "escalates on low confidence" do
      assert Chat::Escalation.escalate?(
        intent: intent("conversation", confidence: 0.5), user_text: "こんにちは", model_role: :fast_chat
      )
    end

    test "escalates for code intent" do
      assert Chat::Escalation.escalate?(
        intent: intent("code"), user_text: "バグを直して", model_role: :fast_chat
      )
    end

    test "escalates on request keywords" do
      assert Chat::Escalation.escalate?(
        intent: intent("conversation"), user_text: "設計を詳しく説明して", model_role: :fast_chat
      )
    end

    test "escalates when reply is unknown-heavy" do
      reply = "資料からは不明です。詳細も不明で、判断できません。"
      assert Chat::Escalation.escalate?(
        intent: intent("rag_lookup"), user_text: "教えて", model_role: :fast_chat, reply: reply
      )
    end

    test "does not escalate for confident casual chat" do
      refute Chat::Escalation.escalate?(
        intent: intent("conversation"), user_text: "ありがとう", model_role: :fast_chat, reply: "どういたしまして"
      )
    end
  end
end
