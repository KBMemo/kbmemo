# frozen_string_literal: true

module Chat
  # Chat::Agent の各フェーズの経過時間・詳細を記録する。
  class AgentTrace
    Step = Struct.new(:key, :label, :status, :elapsed_ms, :detail, :model_role, keyword_init: true) do
      def as_json
        {
          "key" => key.to_s,
          "label" => label,
          "status" => status.to_s,
          "elapsed_ms" => elapsed_ms,
          "detail" => detail,
          "model_role" => model_role&.to_s
        }.compact
      end
    end

    def initialize(broadcaster: nil)
      @broadcaster = broadcaster
      @steps = []
      @started_at = monotonic_ms
      @open_step = nil
      @open_started_at = nil
    end

    def current_step_key
      @open_step&.key
    end

    def run(key, label, model_role: nil)
      finish_open_step!
      @open_step = Step.new(key: key, label: label, status: :running, model_role: model_role)
      @open_started_at = monotonic_ms
      @broadcaster&.trace_step(@open_step, phase: "started")
      result = yield
      finish_open_step!
      @broadcaster&.trace_step(@steps.last, phase: "completed") if @steps.last
      result
    end

    def finish_open_step!(detail: nil)
      return unless @open_step

      elapsed = [ monotonic_ms - @open_started_at, 0 ].max
      @open_step.status = :completed
      @open_step.elapsed_ms = elapsed.round
      @open_step.detail = detail if detail.present?
      @steps << @open_step
      @open_step = nil
      @open_started_at = nil
    end

    def finish_step_detail(detail)
      @open_step.detail = detail if @open_step && detail.present?
    end

    def total_elapsed_ms
      (monotonic_ms - @started_at).round
    end

    def steps
      list = @steps.dup
      list << @open_step if @open_step
      list
    end

    def as_json(account: nil, intent: nil, model_role: nil, escalated: false, interactions: nil)
      payload = {
        "total_elapsed_ms" => total_elapsed_ms,
        "steps" => steps.map(&:as_json),
        "stats" => build_stats(account: account, intent: intent, model_role: model_role, escalated: escalated)
      }
      payload["interactions"] = interactions if interactions.present?
      payload
    end

    private

    def build_stats(account:, intent:, model_role:, escalated:)
      stats = []
      stats << { "label" => "Intent", "value" => intent.to_s } if intent.present?

      model_label = model_display_name(model_role, account: account)
      if model_label.present?
        value = model_label
        value += " (昇格)" if escalated
        stats << { "label" => "モデル", "value" => value }
      end

      stats << { "label" => "経過", "value" => format_duration(total_elapsed_ms / 1000.0) }

      steps.each do |step|
        next unless step.key.to_s == "rag_search" && step.detail.present?

        stats << { "label" => "RAG", "value" => step.detail }
      end

      mcp_step = steps.find { |step| step.key.to_s == "mcp_tools" }
      if mcp_step&.detail.present?
        stats << { "label" => "ツール", "value" => mcp_step.detail }
      end

      stats
    end

    def model_display_name(role, account:)
      return nil if role.blank?

      Chat::ModelRegistry.for(role, account: account).model
    rescue KeyError
      role.to_s
    end

    def format_duration(seconds)
      return "—" if seconds.nil?

      if seconds < 60
        format("%.1f秒", seconds)
      else
        minutes = (seconds / 60).floor
        remainder = seconds % 60
        format("%d分%.0f秒", minutes, remainder)
      end
    end

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end
  end
end
