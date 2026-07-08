# frozen_string_literal: true

module Chat
  # Chat エージェントのパイプライン（dev note §4/§5）。
  #   classify(intent) -> route -> 一次応答 -> 条件を満たせば main(12B) へ昇格
  #
  # ツール（fetch_url / web_search / rag_search / vision / image_generation）は Phase 3 以降。
  # それらを要する intent は、当面 chat 可能なモデルで最善応答しつつ decision.tools を返す。
  class Agent
    # 直接 chat 応答を生成できる役割。他（vision / image_generation / nil）は main へ寄せる。
    CHAT_ROLES = %i[fast_chat main].freeze
    FALLBACK_ROLE = :main

    # intent は intent 名（文字列）。分類の詳細（confidence 等）は classification に持つ。
    Result = Struct.new(
      :reply, :intent, :classification, :model_role, :escalated, :tools, :pending_tools,
      keyword_init: true
    )

    # @param classifier [Chat::IntentClassifier, nil]
    # @param client_factory [#call, nil] role(Symbol) -> Chat::LlmClient
    def initialize(classifier: nil, client_factory: nil)
      @classifier = classifier || Chat::IntentClassifier.new
      @client_factory = client_factory || ->(role) { Chat::ModelRegistry.for(role).build_client }
    end

    # @param messages [Array<Hash>] { role:, content: }（user/assistant 履歴）
    # @param system_prompt [String, nil]
    # @return [Chat::Agent::Result]
    def call(messages:, system_prompt: nil)
      history = normalize_messages(messages)
      user_text = last_user_text(history)

      classification = @classifier.classify(user_text)
      decision = Chat::Router.decide(classification)

      # 有効な user 発話が無ければ LLM を呼ばずに返す（空 POST・二重呼び出しの防止）。
      return build_result(reply: nil, classification: classification, decision: decision, model_role: nil, escalated: false) if user_text.blank?

      primary_role = chat_role(decision.model_role)
      reply = generate(primary_role, system_prompt, history)

      escalated = Chat::Escalation.escalate?(
        intent: classification, user_text: user_text, model_role: primary_role, reply: reply
      )
      final_role = primary_role
      if escalated
        final_role = Chat::Escalation::TOP_ROLE
        reply = generate(final_role, system_prompt, history)
      end

      build_result(
        reply: reply, classification: classification, decision: decision,
        model_role: final_role, escalated: escalated
      )
    end

    private

    def build_result(reply:, classification:, decision:, model_role:, escalated:)
      Result.new(
        reply: reply,
        intent: classification.intent,
        classification: classification,
        model_role: model_role,
        escalated: escalated,
        tools: decision.tools,
        pending_tools: decision.tools.any?
      )
    end

    def generate(role, system_prompt, history)
      messages = []
      messages << { role: "system", content: system_prompt } if system_prompt.present?
      messages.concat(history)
      @client_factory.call(role).chat(messages)
    end

    def chat_role(role)
      CHAT_ROLES.include?(role) ? role : FALLBACK_ROLE
    end

    def normalize_messages(messages)
      Array(messages).filter_map do |entry|
        role = (entry[:role] || entry["role"]).to_s
        content = (entry[:content] || entry["content"]).to_s.strip
        next if content.blank?
        next unless %w[user assistant].include?(role)

        { role: role, content: content }
      end
    end

    def last_user_text(history)
      history.reverse_each.find { |m| m[:role] == "user" }&.fetch(:content, "").to_s
    end
  end
end
