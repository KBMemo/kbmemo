# frozen_string_literal: true

module Chat
  module Tools
    # 複数のランキングリストを Reciprocal Rank Fusion で統合する。
    module RankFusion
      DEFAULT_K = 60

      # @param ranked_lists [Array<Array>] 各リストは memo_id の配列（順位付き）
      # @param k [Integer]
      # @return [Array<Integer>] memo_id を融合スコア降順
      def self.rrf(ranked_lists, k: DEFAULT_K)
        scores = Hash.new(0.0)

        Array(ranked_lists).each do |list|
          Array(list).each_with_index do |memo_id, rank|
            scores[memo_id] += 1.0 / (k + rank + 1)
          end
        end

        scores.sort_by { |_, score| -score }.map(&:first)
      end
    end
  end
end
