# frozen_string_literal: true

module Chat
  # Chat エージェントのパイプライン（dev note §4/§5）。
  #   classify(intent) -> route -> [tools] -> 一次応答 -> 条件を満たせば main(12B) へ昇格
  class Agent
    CHAT_ROLES = %i[fast_chat main].freeze
    FALLBACK_ROLE = :main

    # 徒然内で実行するツール。
    IMPLEMENTED_TOOLS = %i[rag_search memo_search].freeze

    # Nyoy MCP へ委譲可能なツール（Phase 9）。
    DELEGATED_TOOLS = Chat::Tools::NyoyMcpRunner::TOOL_MAP.keys.freeze

    Result = Struct.new(
      :reply, :intent, :classification, :model_role, :escalated, :tools, :pending_tools,
      :rag, :mcp, keyword_init: true
    )

    # @param classifier [Chat::IntentClassifier, nil]
    # @param client_factory [#call, nil] role(Symbol) -> Chat::LlmClient
    # @param rag_search [Chat::Tools::RagSearch, nil]
    # @param mcp_runner [Chat::Tools::NyoyMcpRunner, nil]
    def initialize(classifier: nil, client_factory: nil, rag_search: nil, mcp_runner: nil)
      @classifier = classifier
      @custom_client_factory = client_factory
      @rag_search_factory = rag_search
      @mcp_runner = mcp_runner
    end

    # @param messages [Array<Hash>] { role:, content: }（user/assistant 履歴）
    # @param system_prompt [String, nil]
    # @param account [Account, nil] RAG ツール実行時に必須
    # @return [Chat::Agent::Result]
    def call(messages:, system_prompt: nil, account: nil)
      @account = account
      history = normalize_messages(messages)
      user_text = last_user_text(history)

      classification = classifier.classify(user_text, account: account)
      decision = Chat::Router.decide(classification)

      return build_result(
        reply: nil, classification: classification, decision: decision,
        model_role: nil, escalated: false, rag: nil, mcp: nil, user_text: user_text
      ) if user_text.blank?

      rag_result = run_rag_tool(decision, user_text, account)
      mcp_result = run_mcp_tools(decision, user_text)

      primary_role = chat_role(decision.model_role)
      reply = generate(
        primary_role, system_prompt, classification.intent, history,
        rag_result: rag_result, mcp_result: mcp_result
      )

      escalated = Chat::Escalation.escalate?(
        intent: classification, user_text: user_text, model_role: primary_role, reply: reply
      )
      final_role = primary_role
      if escalated
        final_role = Chat::Escalation::TOP_ROLE
        reply = generate(
          final_role, system_prompt, classification.intent, history,
          rag_result: rag_result, mcp_result: mcp_result
        )
      end

      build_result(
        reply: reply, classification: classification, decision: decision,
        model_role: final_role, escalated: escalated, rag: rag_result, mcp: mcp_result,
        user_text: user_text
      )
    end

    private

    def build_result(reply:, classification:, decision:, model_role:, escalated:, rag:, mcp:, user_text:)
      Result.new(
        reply: reply,
        intent: classification.intent,
        classification: classification,
        model_role: model_role,
        escalated: escalated,
        tools: decision.tools,
        pending_tools: pending_tools?(decision, mcp: mcp, user_text: user_text),
        rag: rag,
        mcp: mcp
      )
    end

    def pending_tools?(decision, mcp:, user_text:)
      decision.tools.any? do |tool|
        next false if IMPLEMENTED_TOOLS.include?(tool)
        next false if mcp&.tools_run&.include?(tool)
        next false if mcp_runner.optional_skip?(tool, user_text: user_text)

        true
      end
    end

    def run_mcp_tools(decision, user_text)
      tools = decision.tools.select { |tool| DELEGATED_TOOLS.include?(tool) }
      return nil if tools.empty?

      mcp_runner.call(tools: tools, user_text: user_text)
    end

    def run_rag_tool(decision, user_text, account)
      return nil unless account
      return nil unless decision.tools.intersect?(IMPLEMENTED_TOOLS)

      factory = @rag_search_factory || Chat::Tools::RagSearch.new(account: account)
      factory.call(user_text: user_text)
    end

    def generate(role, system_prompt, intent, history, rag_result:, mcp_result:)
      effective = system_prompt.presence || Chat::Prompts.system_for(role: role, intent: intent)
      if rag_result&.context_text.present?
        effective = [
          Chat::Prompts::RAG_ANSWER,
          "検索結果:",
          rag_result.context_text
        ].join("\n\n")
      end
      if mcp_result&.context_text.present?
        effective = [
          effective,
          "外部ツール結果（Nyoy MCP）:",
          mcp_result.context_text
        ].compact.join("\n\n")
      end

      messages = []
      messages << { role: "system", content: effective } if effective.present?
      messages.concat(history)
      client_for(role).chat(messages)
    end

    def classifier
      @classifier ||= Chat::IntentClassifier.new
    end

    def mcp_runner
      @mcp_runner ||= Chat::Tools::NyoyMcpRunner.new
    end

    def client_for(role)
      if @custom_client_factory
        @custom_client_factory.call(role)
      else
        Chat::ModelRegistry.for(role, account: @account).build_client
      end
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
