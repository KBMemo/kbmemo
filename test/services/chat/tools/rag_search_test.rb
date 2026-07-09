# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class RagSearchTest < ActiveSupport::TestCase
      class FixedQueryGenerator
        def initialize(queries)
          @queries = queries
        end

        def generate(_user_text)
          RagQueryGenerator::Result.new(queries: @queries, keywords: [], requires_recent_info: false)
        end
      end

      test "retrieves memos visible to account via search_text" do
        account = accounts(:one)
        memos(:one).update_columns(title: "Alpha note", body: "= UniqueAlphaBody\n\ncontent")
        memos(:two).update_columns(title: "Beta", body: "= other")

        result = RagSearch.new(
          account: account,
          query_generator: FixedQueryGenerator.new([ "UniqueAlphaBody" ])
        ).call(user_text: "alpha メモ")

        assert_equal [ "UniqueAlphaBody" ], result.queries
        assert_equal 1, result.hits.size
        assert_equal memos(:one).id, result.hits.first.memo_id
        assert_includes result.context_text, "Alpha note"
        assert_includes result.context_text, "UniqueAlphaBody"
      end

      test "does not return memos outside policy scope" do
        account = accounts(:one)
        other = memos(:two)
        other.update_columns(
          account_id: accounts(:two).id,
          visibility: Memo.visibilities[:owner_read_write],
          title: "SecretTwo",
          body: "SecretTwoBody"
        )

        result = RagSearch.new(
          account: account,
          query_generator: FixedQueryGenerator.new([ "SecretTwoBody" ])
        ).call(user_text: "secret")

        assert_empty result.hits
        assert_equal "", result.context_text
      end

      test "merges results from multiple queries" do
        account = accounts(:one)
        memos(:one).update_columns(title: "First", body: "AlphaKeyword")
        memos(:two).update_columns(title: "Second", body: "BetaKeyword")

        result = RagSearch.new(
          account: account,
          query_generator: FixedQueryGenerator.new([ "AlphaKeyword", "BetaKeyword" ])
        ).call(user_text: "both")

        assert_equal 2, result.hits.size
        titles = result.hits.map(&:title)
        assert_includes titles, "First"
        assert_includes titles, "Second"
      end
    end
  end
end
