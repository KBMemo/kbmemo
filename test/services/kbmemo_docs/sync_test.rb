# frozen_string_literal: true

require "test_helper"

class KbmemoDocsSyncTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @docs_root = Rails.root.join("tmp", "kbmemo_docs_sync_test", SecureRandom.hex(4))
    @docs_root.join("architecture").mkpath
    File.write(
      @docs_root.join("architecture", "hello.adoc"),
      "= Hello Doc\n\nWiki target [[world]].\n",
      encoding: "UTF-8"
    )
  end

  teardown do
    FileUtils.rm_rf(@docs_root)
  end

  test "creates memo under system/docs directory by default" do
    result = KbmemoDocs::Sync.call(account: @account, docs_root: @docs_root)

    assert_equal 1, result.created
    memo = Memo.order(:id).last
    assert_equal "Hello Doc", memo.title
    assert_equal "Wiki target [[world]].\n", memo.body
    assert_equal "architecture/hello.adoc", memo.properties.dig("docs_sync", "source_path")
    assert memo.properties.dig("docs_sync", "read_only")
    assert_equal "system/docs/architecture", memo.memo_directory.full_path
    assert_includes memo.tags.map(&:name), "docs-sync"
  end

  test "creates memo under share dev-docs when sync_target is share" do
    result = KbmemoDocs::Sync.call(account: @account, docs_root: @docs_root, sync_target: "share")

    assert_equal 1, result.created
    memo = Memo.order(:id).last
    assert_equal "share/u-#{@account.id}/dev-docs/architecture", memo.memo_directory.full_path
  end

  test "skips unchanged content on second sync" do
    KbmemoDocs::Sync.call(account: @account, docs_root: @docs_root)
    result = KbmemoDocs::Sync.call(account: @account, docs_root: @docs_root)

    assert_equal 0, result.created
    assert_equal 0, result.updated
    assert_equal 1, result.skipped
  end

  test "updates memo when source file changes" do
    KbmemoDocs::Sync.call(account: @account, docs_root: @docs_root)
    File.write(
      @docs_root.join("architecture", "hello.adoc"),
      "= Hello Doc\n\nUpdated body.\n",
      encoding: "UTF-8"
    )

    result = KbmemoDocs::Sync.call(account: @account, docs_root: @docs_root)

    assert_equal 1, result.updated
    memo = Memo.find_by!("json_extract(properties, '$.docs_sync.source_path') = ?", "architecture/hello.adoc")
    assert_includes memo.body, "Updated body."
  end

  test "dry run does not persist memos" do
    assert_no_difference("Memo.count") do
      result = KbmemoDocs::Sync.call(account: @account, docs_root: @docs_root, dry_run: true)
      assert_equal 1, result.skipped
      assert_includes result.paths.join, "would create"
    end
  end
end
