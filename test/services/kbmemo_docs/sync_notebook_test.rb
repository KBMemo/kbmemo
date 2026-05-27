# frozen_string_literal: true

require "test_helper"

class KbmemoDocsSyncNotebookTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @docs_root = Rails.root.join("tmp", "kbmemo_docs_sync_nb_test", SecureRandom.hex(4))
    @docs_root.join("architecture").mkpath
    File.write(@docs_root.join("architecture", "root.adoc"), "= Root\n\nRoot body.\n", encoding: "UTF-8")
    File.write(@docs_root.join("architecture", "nested.adoc"), "= Nested\n\nNested body.\n", encoding: "UTF-8")
    @docs_root.join("architecture", "deep").mkpath
    File.write(@docs_root.join("architecture", "deep", "leaf.adoc"), "= Leaf\n\nLeaf body.\n", encoding: "UTF-8")
  end

  teardown do
    FileUtils.rm_rf(@docs_root)
  end

  test "registers synced memos in dev-docs notebook with tree" do
    KbmemoDocs::Sync.call(account: @account, docs_root: @docs_root)
    result = KbmemoDocs::SyncNotebook.call(account: @account)

    notebook = result.notebook
    assert_equal "dev-docs", notebook.slug
    assert_equal 3, notebook.notebook_memos.count

    root_entry = notebook.notebook_memos.joins(:memo).find_by!(memos: { title: "Nested" })
    leaf_entry = notebook.notebook_memos.joins(:memo).find_by!(memos: { title: "Leaf" })

    assert_nil root_entry.parent_id
    assert_equal root_entry.id, leaf_entry.parent_id
  end
end
