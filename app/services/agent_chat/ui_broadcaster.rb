# frozen_string_literal: true

module AgentChat
  # ActionCable 経由で AI チャットの進行・モデル応答を配信する（Nyoy ChatUiBroadcaster 相当）。
  class UiBroadcaster
    PREVIEW_LIMIT = 2_000

    def initialize(account:, conversation:, turn_id:)
      @account = account
      @conversation = conversation
      @turn_id = turn_id.to_s
      @seq = 0
    end

    def turn_started
      broadcast(type: "turn_started", conversation_id: @conversation.id)
    end

    def trace_step(step, phase:)
      broadcast(
        type: "trace_step",
        phase: phase.to_s,
        step: step.is_a?(Hash) ? step : step.as_json
      )
    end

    def interaction(step_key:, role:, model: nil, text:, append: false)
      broadcast(
        type: "interaction",
        step_key: step_key.to_s,
        role: role.to_s,
        model: model,
        text: truncate(text),
        append: append
      )
    end

    def tool_context(step_key:, label:, preview:)
      broadcast(
        type: "tool_context",
        step_key: step_key.to_s,
        label: label.to_s,
        preview: truncate(preview)
      )
    end

    def assistant_delta(text:, thinking: false)
      broadcast(
        type: "assistant_delta",
        text: text.to_s,
        thinking: thinking
      )
    end

    def turn_finalized(payload)
      broadcast(type: "turn_finalized", payload: payload)
    end

    def turn_error(error:, settings_url: nil)
      broadcast(
        type: "turn_error",
        error: error.to_s,
        settings_url: settings_url
      )
    end

    private

    def broadcast(payload)
      @seq += 1
      AgentChatAccountChannel.broadcast_to(
        @account,
        payload.merge(
          turn_id: @turn_id,
          seq: @seq,
          conversation_id: @conversation.id
        )
      )
    end

    def truncate(text)
      str = text.to_s
      return str if str.length <= PREVIEW_LIMIT

      "#{str[0, PREVIEW_LIMIT]}…"
    end
  end
end
