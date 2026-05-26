# frozen_string_literal: true

require "test_helper"

class NotebooksMoveMemoTest < ActiveSupport::TestCase
  test "moves entry under parent and renumbers siblings" do
    notebook = notebooks(:one)
    root = notebook_memos(:one_one)
    sibling = notebook_memos(:one_two)
    extra_memo = Memo.create!(
      title: "Tree extra",
      body: "= Extra",
      account: accounts(:one),
      memo_directory: memo_directories(:work)
    )
    child = NotebookMemo.create!(notebook: notebook, memo: extra_memo, parent_id: nil, position: 2)

    Notebooks::MoveMemo.call(notebook: notebook, entry: sibling, parent_id: root.id, position: 0)

    sibling.reload
    assert_equal root.id, sibling.parent_id
    assert_equal 0, sibling.position

    root.reload
    assert_equal 0, root.position
    child.reload
    assert_equal 1, child.position
  end

  test "rejects moving under own descendant" do
    notebook = notebooks(:one)
    root = notebook_memos(:one_one)
    extra_memo = Memo.create!(
      title: "Tree child",
      body: "= Child",
      account: accounts(:one),
      memo_directory: memo_directories(:work)
    )
    child = NotebookMemo.create!(notebook: notebook, memo: extra_memo, parent_id: root.id, position: 0)

    assert_raises(Notebooks::Error) do
      Notebooks::MoveMemo.call(notebook: notebook, entry: root, parent_id: child.id, position: 0)
    end
  end
end
