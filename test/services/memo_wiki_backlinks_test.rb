# frozen_string_literal: true

require "test_helper"

class MemoWikiBacklinksTest < ActiveSupport::TestCase
  setup do
    @one = memos(:one)
    @two = memos(:two)
    @scope = Memo.where(id: [ @one.id, @two.id ])
    MemoWikiLink.delete_all
  end

  test "finds memo linking by title" do
    @one.update_columns(body: "See [[Second memo]] for details.")
    MemoWikiLinkIndex.rebuild_for(@one)

    backlinks = resolver.call
    assert_equal [ @one ], backlinks
  end

  test "finds memo linking by global slug" do
    @one.update_columns(body: "Ref [[#{@two.slug}]]")
    MemoWikiLinkIndex.rebuild_for(@one)

    backlinks = resolver.call
    assert_equal [ @one ], backlinks
  end

  test "finds memo linking by legacy stem slug" do
    @one.update_columns(body: "Ref [[second-memo]]")
    MemoWikiLinkIndex.rebuild_for(@one)

    backlinks = resolver.call
    assert_equal [ @one ], backlinks
  end

  test "finds memo linking by directory path slug" do
    work = memo_directories(:work)
    @two.update_columns(memo_directory_id: work.id)
    @one.update_columns(body: "[[#{work.full_path}/#{@two.slug}]]")
    MemoWikiLinkIndex.rebuild_for(@one)

    backlinks = resolver.call
    assert_equal [ @one ], backlinks
  end

  test "finds memo linking by link:/memos/id href" do
    @one.update_columns(body: "See link:/memos/#{@two.id}[note] for details.")
    MemoWikiLinkIndex.rebuild_for(@one)

    backlinks = resolver.call
    assert_equal [ @one ], backlinks
  end

  test "ignores wiki links inside fenced code blocks" do
    @one.update_columns(body: <<~BODY)
      ```asciidoc
      [[Second memo]]
      ```
    BODY
    MemoWikiLinkIndex.rebuild_for(@one)

    backlinks = resolver.call
    assert_empty backlinks
  end

  test "does not include self" do
    @two.update_columns(body: "[[#{@two.slug}]]")
    MemoWikiLinkIndex.rebuild_for(@two)

    backlinks = resolver.call
    assert_empty backlinks
  end

  test "does not include ambiguous title links that do not resolve to target" do
    @two.update_columns(title: @one.title)
    @one.update_columns(body: "[[#{@one.title}]]")
    MemoWikiLinkIndex.rebuild_for(@one)

    backlinks = resolver.call
    assert_empty backlinks
  end

  test "excludes source memos outside scope" do
    private_memo = memos(:one)
    private_memo.update_columns(body: "See [[Second memo]] for details.")
    MemoWikiLinkIndex.rebuild_for(private_memo)

    backlinks = MemoWikiBacklinks.new(target_memo: @two, scope: Memo.where(id: @two.id)).call
    assert_empty backlinks
  end

  test "sorts by updated_at descending" do
    older = @one
    newer = Memo.create!(
      title: "Newer linker",
      body: "[[Second memo]]",
      memo_directory: memo_directories(:work),
      account: accounts(:one),
      file_committed_at: Time.current
    )
    older.update_columns(body: "[[Second memo]]", updated_at: 2.days.ago)
    newer.update_columns(updated_at: 1.hour.ago)
    MemoWikiLinkIndex.rebuild_for(older)
    MemoWikiLinkIndex.rebuild_for(newer)

    scope = Memo.where(id: [ older.id, newer.id, @two.id ])
    backlinks = MemoWikiBacklinks.new(target_memo: @two, scope: scope).call
    assert_equal [ newer, older ], backlinks
  end

  private

  def resolver
    MemoWikiBacklinks.new(target_memo: @two, scope: @scope)
  end
end
