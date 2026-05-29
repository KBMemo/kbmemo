# frozen_string_literal: true

require "test_helper"

class MemoWikiLinkLabelsTest < ActiveSupport::TestCase
  setup do
    @one = memos(:one)
    @two = memos(:two)
    @scope = Memo.where(id: [@one.id, @two.id])
  end

  test "slug target returns title display" do
    labels = resolver.call([@two.slug])
    entry = labels[@two.slug]
    assert entry[:resolved]
    assert entry[:slug]
    assert_equal @two.title, entry[:display]
    assert_equal @two.id, entry[:memo_id]
    assert_equal @two.uid, entry[:memo_uid]
  end

  test "uid target returns title display" do
    labels = resolver.call([@two.uid])
    entry = labels[@two.uid]
    assert entry[:resolved]
    assert entry[:slug]
    assert_equal @two.title, entry[:display]
    assert_equal @two.id, entry[:memo_id]
    assert_equal @two.uid, entry[:memo_uid]
  end

  test "title target keeps target as display" do
    labels = resolver.call(["Second memo"])
    entry = labels["Second memo"]
    assert entry[:resolved]
    assert_not entry[:slug]
    assert_equal "Second memo", entry[:display]
    assert_equal @two.id, entry[:memo_id]
  end

  test "missing target is unresolved" do
    labels = resolver.call(["Missing memo"])
    entry = labels["Missing memo"]
    assert_not entry[:resolved]
    assert_equal "Missing memo", entry[:display]
    assert_nil entry[:memo_id]
  end

  private

  def resolver
    MemoWikiLinkLabels.new(scope: @scope, source_memo: @one)
  end
end
