# frozen_string_literal: true

module AgentChat
  class MemoReferences
    MAX_COUNT = 5
    MAX_BODY_CHARS = 12_000
    MAX_TOTAL_CHARS = 30_000

    Reference = Data.define(:id, :title, :body, :body_chars) do
      def as_json
        { id: id, title: title, body_chars: body_chars }
      end
    end

    def self.resolve(scope:, ids:)
      normalized_ids = Array(ids).filter_map { |id| Integer(id, exception: false) }.uniq.first(MAX_COUNT)
      by_id = scope.where(id: normalized_ids).index_by(&:id)
      remaining = MAX_TOTAL_CHARS

      normalized_ids.filter_map do |id|
        memo = by_id[id]
        next unless memo

        full_body = memo.body.to_s
        body = full_body.first([ MAX_BODY_CHARS, remaining ].min)
        remaining -= body.length
        Reference.new(id: memo.id, title: memo.title, body: body, body_chars: full_body.length)
      end
    end

    def self.context_text(references)
      JSON.generate(
        Array(references).map do |reference|
          {
            id: reference.id,
            title: reference.title,
            content: reference.body.presence || "（本文なし）"
          }
        end
      )
    end
  end
end
