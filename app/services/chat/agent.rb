# frozen_string_literal: true

module Chat
  # Chat エージェントのパイプライン（dev note §4/§5）。
  #   classify(intent) -> route -> [tools] -> 一次応答 -> 条件を満たせば main(12B) へ昇格
  class Agent
    CHAT_ROLES = %i[fast_chat main].freeze
    FALLBACK_ROLE = :main
    MESSAGE_PREVIEW_LIMIT = 3_000

    # 徒然内で実行するツール。
    IMPLEMENTED_TOOLS = %i[rag_search memo_search].freeze

    # Nyoy MCP へ委譲可能なツール（Phase 9）。
    DELEGATED_TOOLS = Chat::Tools::NyoyMcpRunner::TOOL_MAP.keys.freeze

    Result = Struct.new(
      :reply, :intent, :classification, :model_role, :escalated, :tools, :pending_tools,
      :rag, :mcp, :trace, :interactions, keyword_init: true
    )

    TraceBroadcaster = Struct.new(:ui) do
      def trace_step(step, phase:)
        ui.trace_step(step, phase: phase.to_s)
      end
    end

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
    # @param broadcaster [AgentChat::UiBroadcaster, nil]
    # @return [Chat::Agent::Result]
    # @param enabled_mcp_tools [Array<String>, nil] ユーザーが有効化した Nyoy MCP ツール名
    def call(messages:, system_prompt: nil, account: nil, broadcaster: nil, enabled_mcp_tools: nil)
      @account = account
      @broadcaster = broadcaster
      @enabled_mcp_tools = normalize_enabled_mcp_tools(enabled_mcp_tools)
      @interaction_log = Chat::AgentInteractionLog.new(broadcaster: broadcaster)
      trace = Chat::AgentTrace.new(broadcaster: broadcaster && TraceBroadcaster.new(broadcaster))
      broadcaster&.turn_started

      history = normalize_messages(messages)
      user_text = last_user_text(history)

      classification = trace.run(:intent, "Intent 分類") do
        result = classify_intent(user_text, account: account, step_key: :intent)
        trace.finish_step_detail(intent_step_detail(result))
        result
      end
      decision = Chat::Router.decide(classification)

      return build_result(
        reply: nil, classification: classification, decision: decision,
        model_role: nil, escalated: false, rag: nil, mcp: nil, user_text: user_text,
        trace: trace, interactions: @interaction_log
      ) if user_text.blank?

      rag_result = run_rag_tool(decision, user_text, account, trace: trace)
      mcp_result = run_mcp_tools(decision, user_text, trace: trace)

      primary_role = chat_role(decision.model_role)
      reply = trace.run(:generate, "応答生成", model_role: primary_role) do
        trace.finish_step_detail(model_label_for(primary_role))
        generate(
          primary_role, system_prompt, classification.intent, history,
          rag_result: rag_result, mcp_result: mcp_result, step_key: trace.current_step_key
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
            rag_result: rag_result, mcp_result: mcp_result, step_key: trace.current_step_key
          )
        end
      end

      build_result(
        reply: reply, classification: classification, decision: decision,
        model_role: final_role, escalated: escalated, rag: rag_result, mcp: mcp_result,
        user_text: user_text, trace: trace, interactions: @interaction_log
      )
    end

    private

    def build_result(reply:, classification:, decision:, model_role:, escalated:, rag:, mcp:, user_text:, trace:, interactions:)
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
        trace: trace,
        interactions: interactions
      )
    end

    def classify_intent(user_text, account:, step_key:)
      model = model_label_for(:intent)
      @interaction_log.record(
        step_key: step_key,
        role: "request",
        model: model,
        text: messages_preview([
          { role: "system", content: Chat::Prompts::INTENT_CLASSIFIER },
          { role: "user", content: user_text }
        ])
      )

      result = classifier.classify(user_text, account: account, stream: @broadcaster.present?) do |delta|
        record_model_delta(step_key: step_key, model: model, delta: delta)
      end

      result
    end

    def pending_tools?(decision, mcp:, user_text:)
      decision.tools.any? do |tool|
        next false if IMPLEMENTED_TOOLS.include?(tool)
        next false unless delegated_tool_enabled?(tool)
        next false if mcp&.tools_run&.include?(tool) || mcp_tool_ran?(mcp, tool)
        next false if mcp_runner.optional_skip?(tool, user_text: user_text)

        true
      end
    end

    def mcp_tool_ran?(mcp, tool)
      mcp_name = Chat::Tools::NyoyMcpRunner::TOOL_MAP[tool]
      return false unless mcp_name

      Array(mcp&.tools_run).map(&:to_s).include?(mcp_name)
    end

    def delegated_tool_enabled?(tool)
      return true if @enabled_mcp_tools.nil?

      mcp_name = Chat::Tools::NyoyMcpRunner::TOOL_MAP[tool]
      return false unless mcp_name

      @enabled_mcp_tools.include?(mcp_name)
    end

    def run_mcp_tools(decision, user_text, trace:)
      router_mcp_names = decision.tools.filter_map do |tool|
        next unless DELEGATED_TOOLS.include?(tool)
        next unless delegated_tool_enabled?(tool)

        Chat::Tools::NyoyMcpRunner::TOOL_MAP[tool]
      end.uniq
      mcp_names = (router_mcp_names + extra_enabled_mcp_names(router_mcp_names)).uniq
      return nil if mcp_names.empty?
      return nil if @enabled_mcp_tools == []

      trace.run(:mcp_tools, "外部ツール（Nyoy MCP）") do
        result = mcp_runner.call(mcp_names: mcp_names, user_text: user_text)
        @interaction_log.tool_context(
          step_key: :mcp_tools,
          label: "Nyoy MCP",
          preview: result.context_text
        )
        trace.finish_step_detail(mcp_step_detail(result))
        result
      end
    end

    def normalize_enabled_mcp_tools(raw)
      return nil if raw.nil?

      Array(raw).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end

    def extra_enabled_mcp_names(router_mcp_names)
      return [] unless @enabled_mcp_tools.is_a?(Array) && @enabled_mcp_tools.any?

      @enabled_mcp_tools.filter_map do |name|
        next if router_mcp_names.include?(name)
        next unless Chat::Tools::NyoyMcpRunner.directly_invocable?(name)

        name
      end.uniq
    end

    def run_rag_tool(decision, user_text, account, trace:)
      return nil unless account
      return nil unless decision.tools.intersect?(IMPLEMENTED_TOOLS)

      trace.run(:rag_search, "メモ検索（RAG）") do
        factory = @rag_search_factory || Chat::Tools::RagSearch.new(account: account)
        result = factory.call(user_text: user_text)
        @interaction_log.tool_context(
          step_key: :rag_search,
          label: "RAG コンテキスト",
          preview: result.context_text
        )
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

    def generate(role, system_prompt, intent, history, rag_result:, mcp_result:, step_key:)
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

      model = model_label_for(role)
      @interaction_log.record(
        step_key: step_key,
        role: "request",
        model: model,
        text: messages_preview(messages)
      )

      stream = @broadcaster.present?
      client_for(role).chat(messages, stream: stream) do |delta|
        record_model_delta(step_key: step_key, model: model, delta: delta)
      end
    end

    def record_model_delta(step_key:, model:, delta:)
      thinking = delta[:thinking]
      content = delta[:content]

      if Chat::LlmClient.streamable_chunk?(thinking)
        @interaction_log.record(
          step_key: step_key,
          role: "thinking",
          model: model,
          text: thinking,
          append: true
        )
      end

      return unless Chat::LlmClient.streamable_chunk?(content)

      @interaction_log.record(
        step_key: step_key,
        role: "response",
        model: model,
        text: content,
        append: true
      )
    end

    def messages_preview(messages)
      messages.map do |message|
        role = message[:role] || message["role"]
        content = (message[:content] || message["content"]).to_s
        content = "#{content[0, MESSAGE_PREVIEW_LIMIT]}…" if content.length > MESSAGE_PREVIEW_LIMIT
        "[#{role}] #{content}"
      end.join("\n\n")
    end

    def classifier
      @classifier ||= Chat::IntentClassifier.new
    end

    def mcp_runner
      @mcp_runner ||= Chat::Tools::NyoyMcpRunner.new(account: @account)
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
