# frozen_string_literal: true

module Chat
  # モデルとのやり取りログ（ActionCable 配信 + 履歴復元用）。
  class AgentInteractionLog
    Entry = Struct.new(:step_key, :role, :model, :text, keyword_init: true) do
      def as_json
        {
          "step_key" => step_key.to_s,
          "role" => role.to_s,
          "model" => model,
          "text" => text
        }.compact
      end
    end

    PREVIEW_LIMIT = 4_000

    def initialize(broadcaster: nil)
      @broadcaster = broadcaster
      @entries = []
    end

    def record(step_key:, role:, model: nil, text:, append: false)
      chunk = text.to_s
      return if chunk.empty?

      entry = @entries.last
      if append && entry && entry.step_key.to_s == step_key.to_s && entry.role.to_s == role.to_s
        entry.text << chunk
      else
        entry = Entry.new(step_key: step_key, role: role, model: model, text: +"")
        entry.text << chunk
        @entries << entry
      end

      @broadcaster&.interaction(
        step_key: step_key,
        role: role,
        model: model,
        text: chunk,
        append: append
      )
    end

    def tool_context(step_key:, label:, preview:)
      text = preview.to_s
      return if text.blank?

      record(step_key: step_key, role: "tool", model: label, text: text, append: false)
      @broadcaster&.tool_context(step_key: step_key, label: label, preview: text)
    end

    def as_json
      @entries.map do |entry|
        json = entry.as_json
        json["text"] = truncate(json["text"]) if json["text"].present?
        json
      end
    end

    private

    def truncate(text)
      str = text.to_s
      return str if str.length <= PREVIEW_LIMIT

      "#{str[0, PREVIEW_LIMIT]}…"
    end
  end
end
