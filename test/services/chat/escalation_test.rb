# frozen_string_literal: true

require "test_helper"

module Chat
  class EscalationTest < ActiveSupport::TestCase
    setup { Chat::ModelRegistry.reset! }
    teardown { Chat::ModelRegistry.reset! }

    def intent(name, confidence: 0.9)
      Chat::IntentClassifier::Result.new(
        intent: name, confidence: confidence, needs_tool: false, reason: ""
      )
    end

    def with_heavier_top_role
      original = Chat::ModelRegistry.method(:for)
      main_cfg = Chat::ModelRegistry::Config.new(
        role: :main, provider: :llama_cpp, base_url: "http://heavy:10012",
        model: "gemma-4-12b", temperature: 0.5, api_key: nil
      )
      fast_cfg = Chat::ModelRegistry::Config.new(
        role: :fast_chat, provider: :llama_cpp, base_url: "http://fast:10011",
        model: "gemma-4-e4b", temperature: 0.4, api_key: nil
      )
      Chat::ModelRegistry.define_singleton_method(:for) do |role, account: nil|
        case role.to_sym
        when :main then main_cfg
        when :fast_chat then fast_cfg
        else original.call(role, account: account)
        end
      end
      yield
    ensure
      Chat::ModelRegistry.define_singleton_method(:for, original)
      Chat::ModelRegistry.reset!
    end

    test "never escalates when already on main" do
      refute Chat::Escalation.escalate?(
        intent: intent("code", confidence: 0.1), user_text: "実装して", model_role: :main
      )
    end

    test "does not escalate when main matches fast_chat" do
      refute Chat::Escalation.escalate?(
        intent: intent("conversation", confidence: 0.5), user_text: "こんにちは", model_role: :fast_chat
      )
    end

    test "escalates on low confidence when top role is heavier" do
      with_heavier_top_role do
        assert Chat::Escalation.escalate?(
          intent: intent("conversation", confidence: 0.5), user_text: "こんにちは", model_role: :fast_chat
        )
      end
    end

    test "escalates for code intent when top role is heavier" do
      with_heavier_top_role do
        assert Chat::Escalation.escalate?(
          intent: intent("code"), user_text: "バグを直して", model_role: :fast_chat
        )
      end
    end

    test "escalates on request keywords when top role is heavier" do
      with_heavier_top_role do
        assert Chat::Escalation.escalate?(
          intent: intent("conversation"), user_text: "設計を詳しく説明して", model_role: :fast_chat
        )
      end
    end

    test "escalates when reply is unknown-heavy and top role is heavier" do
      reply = "資料からは不明です。詳細も不明で、判断できません。"
      with_heavier_top_role do
        assert Chat::Escalation.escalate?(
          intent: intent("rag_lookup"), user_text: "教えて", model_role: :fast_chat, reply: reply
        )
      end
    end

    test "does not escalate for confident casual chat" do
      refute Chat::Escalation.escalate?(
        intent: intent("conversation"), user_text: "ありがとう", model_role: :fast_chat, reply: "どういたしまして"
      )
    end
  end
end
