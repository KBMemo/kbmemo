# frozen_string_literal: true

module Chat
  module Tools
    # Phase 5a: pgroonga（Memo.search_text）を retriever に使う RAG 検索。
    class RagSearch
      DEFAULT_LIMIT = 5
      MAX_EXCERPT_CHARS = 2_000

      Hit = Struct.new(:memo_id, :title, :excerpt, keyword_init: true)
      Result = Struct.new(:queries, :hits, :context_text, keyword_init: true)

      # @param account [Account] Pundit の user としてメモ閲覧可能範囲を絞る
      # @param scope [ActiveRecord::Relation, nil] 省略時は MemoPolicy::Scope
      # @param query_generator [Chat::Tools::RagQueryGenerator, nil]
      def initialize(account:, scope: nil, query_generator: nil)
        @account = account
        @scope = scope
        @query_generator = query_generator || RagQueryGenerator.new
      end

      # @param user_text [String]
      # @return [Chat::Tools::RagSearch::Result]
      def call(user_text:)
        generated = @query_generator.generate(user_text)
        hits = retrieve(generated.queries)
        Result.new(
          queries: generated.queries,
          hits: hits,
          context_text: format_context(hits)
        )
      end

      private

      def retrieve(queries)
        ranked = {}
        Array(queries).each do |query|
          q = query.to_s.strip
          next if q.blank?

          searchable_scope.search_text(q).limit(DEFAULT_LIMIT).each_with_index do |memo, idx|
            entry = ranked[memo.id]
            if entry.nil? || idx < entry[:rank]
              ranked[memo.id] = { memo: memo, rank: idx }
            end
          end
        end

        ranked.values
          .sort_by { |h| h[:rank] }
          .first(DEFAULT_LIMIT)
          .map do |h|
            memo = h[:memo]
            Hit.new(
              memo_id: memo.id,
              title: memo.title,
              excerpt: excerpt_for(memo.body)
            )
          end
      end

      def searchable_scope
        @scope || MemoPolicy::Scope.new(@account, Memo.all).resolve
      end

      def excerpt_for(body)
        text = body.to_s.strip
        return "（本文なし）" if text.blank?
        return text if text.length <= MAX_EXCERPT_CHARS

        "#{text[0, MAX_EXCERPT_CHARS]}\n…（以降 #{text.length - MAX_EXCERPT_CHARS} 文字省略）"
      end

      def format_context(hits)
        return "" if hits.empty?

        hits.map.with_index(1) do |hit, index|
          parts = [ "### 資料 #{index}: #{hit.title}" ]
          parts << "memo_id: #{hit.memo_id}"
          parts << hit.excerpt
          parts.join("\n")
        end.join("\n\n")
      end
    end
  end
end
