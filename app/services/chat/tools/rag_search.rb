# frozen_string_literal: true

module Chat
  module Tools
    # RAG 検索: pgroonga（lexical, Phase 5a）+ pgvector（semantic, Phase 5b）を RRF で統合。
    class RagSearch
      DEFAULT_LIMIT = 5
      MAX_EXCERPT_CHARS = 2_000

      Hit = Struct.new(:memo_id, :title, :excerpt, :sources, keyword_init: true)
      Result = Struct.new(:queries, :hits, :context_text, :semantic_used, keyword_init: true)

      # @param account [Account]
      # @param scope [ActiveRecord::Relation, nil]
      # @param query_generator [Chat::Tools::RagQueryGenerator, nil]
      # @param embedding_client [Chat::EmbeddingClient, nil] nil で ModelRegistry から生成
      # @param semantic_enabled [Boolean] false で semantic を無効化（テスト用）
      def initialize(account:, scope: nil, query_generator: nil, embedding_client: nil, semantic_enabled: true)
        @account = account
        @scope = scope
        @query_generator = query_generator || RagQueryGenerator.new
        @embedding_client = embedding_client
        @semantic_enabled = semantic_enabled
      end

      def call(user_text:)
        generated = @query_generator.generate(user_text)
        lexical = lexical_retrieve(generated.queries)
        semantic = semantic_retrieve(user_text, generated.queries)
        hits = merge_hits(lexical, semantic)

        Result.new(
          queries: generated.queries,
          hits: hits,
          context_text: format_context(hits),
          semantic_used: semantic.any?
        )
      end

      private

      def lexical_retrieve(queries)
        ranked = {}
        Array(queries).each do |query|
          q = query.to_s.strip
          next if q.blank?

          searchable_scope.search_text(q).limit(DEFAULT_LIMIT).each_with_index do |memo, idx|
            entry = ranked[memo.id]
            if entry.nil? || idx < entry[:rank]
              ranked[memo.id] = {
                memo: memo,
                rank: idx,
                excerpt: excerpt_for(memo.body)
              }
            end
          end
        end

        ranked.values
          .sort_by { |h| h[:rank] }
          .first(DEFAULT_LIMIT)
          .map do |h|
            {
              memo_id: h[:memo].id,
              title: h[:memo].title,
              excerpt: h[:excerpt],
              source: :lexical
            }
          end
      end

      def semantic_retrieve(user_text, queries)
        return [] unless @semantic_enabled
        return [] unless MemoEmbeddingChunk.pgvector_enabled?

        text = user_text.to_s.strip.presence || Array(queries).find { |q| q.to_s.strip.present? }
        return [] if text.blank?

        vector = embedding_client.embed(text, kind: :query)
        MemoEmbeddingChunk.nearest_to(
          vector,
          memo_ids_scope: searchable_scope,
          limit: DEFAULT_LIMIT
        ).map do |chunk|
          {
            memo_id: chunk.memo_id,
            title: chunk.memo.title,
            excerpt: excerpt_for(chunk.content),
            source: :semantic
          }
        end
      rescue Chat::EmbeddingClient::ConnectionError, Chat::EmbeddingClient::Error
        []
      end

      def merge_hits(lexical, semantic)
        lexical_ids = lexical.map { |h| h[:memo_id] }
        semantic_ids = semantic.map { |h| h[:memo_id] }
        fused_ids = RankFusion.rrf([ lexical_ids, semantic_ids ]).first(DEFAULT_LIMIT)

        by_id = {}
        lexical.each do |h|
          by_id[h[:memo_id]] = h.merge(sources: [ h[:source] ])
        end
        semantic.each do |h|
          existing = by_id[h[:memo_id]]
          if existing
            existing[:sources] |= [ h[:source] ]
            existing[:excerpt] = h[:excerpt]
          else
            by_id[h[:memo_id]] = h.merge(sources: [ h[:source] ])
          end
        end

        fused_ids.filter_map do |memo_id|
          entry = by_id[memo_id]
          next unless entry

          Hit.new(
            memo_id: memo_id,
            title: entry[:title],
            excerpt: entry[:excerpt],
            sources: entry[:sources]
          )
        end
      end

      def embedding_client
        @embedding_client ||= Chat::ModelRegistry.for(:embedding).build_embedding_client
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
          parts << "sources: #{Array(hit.sources).join(', ')}" if hit.sources.present?
          parts << hit.excerpt
          parts.join("\n")
        end.join("\n\n")
      end
    end
  end
end
