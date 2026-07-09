# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class RankFusionTest < ActiveSupport::TestCase
      test "rrf prefers items ranked high in multiple lists" do
        list_a = [ 1, 2, 3 ]
        list_b = [ 2, 4, 1 ]
        fused = RankFusion.rrf([ list_a, list_b ])

        assert_equal 2, fused.first
        assert_includes fused, 1
      end

      test "rrf returns empty for empty input" do
        assert_equal [], RankFusion.rrf([])
      end
    end
  end
end
