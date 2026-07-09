# frozen_string_literal: true

module Chat
  # Chat エージェントのパイプライン（dev note §4/§5）。
  #   classify(intent) -> route -> [tools] -> 一次応答 -> 条件を満たせば main(12B) へ昇格
  class Agent
    CHAT_ROLES = %i[fast_chat main].freeze
    FALLBACK_ROLE = :main

    # Phase 5a で実装済みのツール。未実装ツールが残るとき pending_tools が true になる。
    IMPLEMENTED_TOOLS = %i[rag_search memo_search].freeze

    Result = Struct.new(
      :reply, :intent, :classification, :model_role, :escalated, :tools, :pending_tools,
      :rag, keyword_init: true
    )

    # @param classifier [Chat::IntentClassifier, nil]
    # @param client_factory [#call, nil] role(Symbol) -> Chat::LlmClient
    # @param rag_search [Chat::Tools::RagSearch, nil]
    def initialize(classifier: nil, client_factory: nil, rag_search: nil)
      @classifier = classifier || Chat::IntentClassifier.new
      @client_factory = client_factory || ->(role) { Chat::ModelRegistry.for(role).build_client }
      @rag_search_factory = rag_search
    end

    # @param messages [Array<Hash>] { role:, content: }（user/assistant 履歴）
    # @param system_prompt [String, nil]
    # @param account [Account, nil] RAG ツール実行時に必須
    # @return [Chat::Agent::Result]
    def call(messages:, system_prompt: nil, account: nil)
      history = normalize_messages(messages)
      user_text = last_user_text(history)

      classification = @classifier.classify(user_text)
      decision = Chat::Router.decide(classification)

      return build_result(
        reply: nil, classification: classification, decision: decision,
        model_role: nil, escalated: false, rag: nil
      ) if user_text.blank?

      rag_result = run_rag_tool(decision, user_text, account)

      primary_role = chat_role(decision.model_role)
      reply = generate(primary_role, system_prompt, classification.intent, history, rag_result: rag_result)

      escalated = Chat::Escalation.escalate?(
        intent: classification, user_text: user_text, model_role: primary_role, reply: reply
      )
      final_role = primary_role
      if escalated
        final_role = Chat::Escalation::TOP_ROLE
        reply = generate(final_role, system_prompt, classification.intent, history, rag_result: rag_result)
      end

      build_result(
        reply: reply, classification: classification, decision: decision,
        model_role: final_role, escalated: escalated, rag: rag_result
      )
    end

    private

    def build_result(reply:, classification:, decision:, model_role:, escalated:, rag:)
      Result.new(
        reply: reply,
        intent: classification.intent,
        classification: classification,
        model_role: model_role,
        escalated: escalated,
        tools: decision.tools,
        pending_tools: decision.tools.any? { |tool| !IMPLEMENTED_TOOLS.include?(tool) },
        rag: rag
      )
    end

    def run_rag_tool(decision, user_text, account)
      return nil unless account
      return nil unless decision.tools.intersect?(IMPLEMENTED_TOOLS)

      factory = @rag_search_factory || Chat::Tools::RagSearch.new(account: account)
      factory.call(user_text: user_text)
    end

    def generate(role, system_prompt, intent, history, rag_result:)
      effective = system_prompt.presence || Chat::Prompts.system_for(role: role, intent: intent)
      if rag_result&.context_text.present?
        effective = [
          Chat::Prompts::RAG_ANSWER,
          "検索結果:",
          rag_result.context_text
        ].join("\n\n")
      end

      messages = []
      messages << { role: "system", content: effective } if effective.present?
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
