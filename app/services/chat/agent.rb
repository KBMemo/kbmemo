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
      :rag, :mcp, :trace, keyword_init: true
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
      trace = Chat::AgentTrace.new
      history = normalize_messages(messages)
      user_text = last_user_text(history)

      classification = trace.run(:intent, "Intent 分類") do
        result = classifier.classify(user_text, account: account)
        trace.finish_step_detail(intent_step_detail(result))
        result
      end
      decision = Chat::Router.decide(classification)

      return build_result(
        reply: nil, classification: classification, decision: decision,
        model_role: nil, escalated: false, rag: nil, mcp: nil, user_text: user_text, trace: trace
      ) if user_text.blank?

      rag_result = run_rag_tool(decision, user_text, account, trace: trace)
      mcp_result = run_mcp_tools(decision, user_text, trace: trace)

      primary_role = chat_role(decision.model_role)
      reply = trace.run(:generate, "応答生成", model_role: primary_role) do
        trace.finish_step_detail(model_label_for(primary_role))
        generate(
          primary_role, system_prompt, classification.intent, history,
          rag_result: rag_result, mcp_result: mcp_result
        )
      end

      escalated = Chat::Escalation.escalate?(
        intent: classification, user_text: user_text, model_role: primary_role, reply: reply,
        account: @account
      )
      final_role = primary_role
      if escalated
        trace.run(:escalate, "モデル昇格") do
          trace.finish_step_detail("#{primary_role} → #{Chat::Escalation::TOP_ROLE}")
          true
        end
        final_role = Chat::Escalation::TOP_ROLE
        reply = trace.run(:generate_escalated, "応答生成（昇格）", model_role: final_role) do
          trace.finish_step_detail(model_label_for(final_role))
          generate(
            final_role, system_prompt, classification.intent, history,
            rag_result: rag_result, mcp_result: mcp_result
          )
        end
      end

      build_result(
        reply: reply, classification: classification, decision: decision,
        model_role: final_role, escalated: escalated, rag: rag_result, mcp: mcp_result,
        user_text: user_text, trace: trace
      )
    end

    private

    def build_result(reply:, classification:, decision:, model_role:, escalated:, rag:, mcp:, user_text:, trace:)
      Result.new(
        reply: reply,
        intent: classification.intent,
        classification: classification,
        model_role: model_role,
        escalated: escalated,
        tools: decision.tools,
        pending_tools: pending_tools?(decision, mcp: mcp, user_text: user_text),
        rag: rag,
        mcp: mcp,
        trace: trace
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

    def run_mcp_tools(decision, user_text, trace:)
      tools = decision.tools.select { |tool| DELEGATED_TOOLS.include?(tool) }
      return nil if tools.empty?

      trace.run(:mcp_tools, "外部ツール（Nyoy MCP）") do
        result = mcp_runner.call(tools: tools, user_text: user_text)
        trace.finish_step_detail(mcp_step_detail(result))
        result
      end
    end

    def run_rag_tool(decision, user_text, account, trace:)
      return nil unless account
      return nil unless decision.tools.intersect?(IMPLEMENTED_TOOLS)

      trace.run(:rag_search, "メモ検索（RAG）") do
        factory = @rag_search_factory || Chat::Tools::RagSearch.new(account: account)
        result = factory.call(user_text: user_text)
        trace.finish_step_detail(rag_step_detail(result))
        result
      end
    end

    def intent_step_detail(classification)
      confidence = classification.confidence
      label = classification.intent.to_s
      return label if confidence.nil?

      format("%s (%.0f%%)", label, confidence * 100)
    end

    def rag_step_detail(result)
      parts = [ "#{result.hits.size}件" ]
      parts << "semantic" if result.semantic_used
      parts.join(" · ")
    end

    def mcp_step_detail(result)
      run = Array(result.tools_run).map(&:to_s)
      return "スキップ" if run.empty?

      run.join(", ")
    end

    def model_label_for(role)
      Chat::ModelRegistry.for(role, account: @account).model
    rescue KeyError
      role.to_s
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
