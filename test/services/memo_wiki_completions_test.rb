# frozen_string_literal: true

require "test_helper"

class MemoWikiCompletionsTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @scope = MemoPolicy::Scope.new(@account, Memo.all).resolve
    @source = memos(:one)
    @target = memos(:two)
  end

  test "includes title slug and full path for searchable memo" do
    entries = completions.call("Second")
    inserts = entries.map { |e| e[:insert] }
    assert_includes inserts, @target.title
    assert_includes inserts, @target.slug
    assert_includes inserts, "home/u-1/work/#{@target.slug}"
  end

  test "empty query still suggests slug in same directory" do
    entries = completions.call("")
    inserts = entries.map { |e| e[:insert] }
    assert_includes inserts, @target.slug
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
