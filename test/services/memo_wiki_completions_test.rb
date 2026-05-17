# frozen_string_literal: true

require "test_helper"

class MemoWikiCompletionsTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @scope = MemoPolicy::Scope.new(@account, Memo.all).resolve
    @source = memos(:one)
    @target = memos(:two)
  end

  test "suggests title label with slug insert for searchable memo" do
    entries = completions.call("Second")
    entry = entries.find { |e| e[:label] == @target.title }
    assert entry
    assert_equal @target.slug, entry[:insert]
    assert_not entries.any? { |e| e[:label] == @target.slug }
  end

  test "empty query suggests title label with slug insert" do
    entries = completions.call("")
    entry = entries.find { |e| e[:label] == @target.title }
    assert entry
    assert_equal @target.slug, entry[:insert]
  end

  test "excludes source memo from results" do
    entries = completions.call("")
    assert_not entries.any? { |e| e[:label] == @source.title }
  end

  private

  def completions
    MemoWikiCompletions.new(scope: @scope, source_memo: @source)
  end
end
