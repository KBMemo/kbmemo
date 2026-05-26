# frozen_string_literal: true

require "test_helper"

class MemoWikiLinkIndexTest < ActiveSupport::TestCase
  setup do
    @one = memos(:one)
    @two = memos(:two)
    MemoWikiLink.delete_all
  end

  test "rebuild_for creates outgoing edges" do
    @one.update_columns(body: "See [[#{@two.title}]]")
    MemoWikiLinkIndex.rebuild_for(@one)

    assert_equal [@two.id], @one.outgoing_wiki_links.pluck(:target_memo_id)
  end

  test "rebuild_for replaces stale edges" do
    @one.update_columns(body: "See [[#{@two.title}]]")
    MemoWikiLinkIndex.rebuild_for(@one)
    @one.update_columns(body: "No links")
    MemoWikiLinkIndex.rebuild_for(@one)

    assert_empty @one.outgoing_wiki_links
  end

  test "rebuild_inbound_for reindexes sources after target title change" do
    @one.update_columns(body: "See [[#{@two.slug}]]")
    MemoWikiLinkIndex.rebuild_for(@one)

    @two.update!(title: "Renamed target")

    assert_equal [@two.id], @one.reload.outgoing_wiki_links.pluck(:target_memo_id)
  end

  test "memo after_commit rebuilds outgoing links on body save" do
    @one.update!(body: "See [[#{@two.title}]]")

    assert_equal [@two.id], @one.outgoing_wiki_links.pluck(:target_memo_id)
  end
end
