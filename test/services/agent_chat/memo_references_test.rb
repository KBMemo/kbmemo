# frozen_string_literal: true

require "test_helper"

module AgentChat
  class MemoReferencesTest < ActiveSupport::TestCase
    test "resolve preserves requested order and only uses records in scope" do
      references = MemoReferences.resolve(
        scope: Memo.where(id: memos(:one).id),
        ids: [ memos(:two).id, memos(:one).id ]
      )

      assert_equal [ memos(:one).id ], references.map(&:id)
      assert_equal "First memo", references.first.title
    end

    test "resolve limits count and total body size" do
      scope = Memo.where(id: [ memos(:one).id, memos(:two).id ])
      references = MemoReferences.resolve(scope: scope, ids: [ memos(:one).id, memos(:two).id ] * 4)

      assert_equal 2, references.size
      assert_operator references.sum { |reference| reference.body.length }, :<=, MemoReferences::MAX_TOTAL_CHARS
    end

    test "context_text serializes memo content as JSON data" do
      references = MemoReferences.resolve(scope: Memo.all, ids: [ memos(:one).id ])

      data = JSON.parse(MemoReferences.context_text(references))
      assert_equal memos(:one).id, data.first["id"]
      assert_equal "First memo", data.first["title"]
      assert_equal "= Hello", data.first["content"]
    end
  end
end
