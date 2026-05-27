# frozen_string_literal: true

require "test_helper"

class MemoAdocIncludesTest < ActiveSupport::TestCase
  setup do
    @docs_root = Rails.root.join("tmp", "memo_adoc_includes_test", SecureRandom.hex(4))
    @docs_root.join("architecture").mkpath
    File.write(
      @docs_root.join("architecture", "child.adoc"),
      "= Child title\n\nChild body.\n",
      encoding: "UTF-8"
    )
    File.write(
      @docs_root.join("architecture", "parent.adoc"),
      "= Parent\n\nBefore.\n\ninclude::child.adoc[]\n\nAfter.\n",
      encoding: "UTF-8"
    )

    @memo = memos(:one)
    @memo.update!(
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/parent.adoc",
          "read_only" => true
        }
      }
    )
  end

  teardown do
    FileUtils.rm_rf(@docs_root)
  end

  test "expands include from docs root relative to source file" do
    body = "include::child.adoc[]\n"
    expanded = MemoAdocIncludes.new(memo: @memo, docs_root: @docs_root).expand(body)

    assert_includes expanded, "Child body."
    assert_not_includes expanded, "include::"
    assert_not_includes expanded, "Child title"
  end

  test "leaves include inside fenced code unchanged" do
    body = "```\ninclude::child.adoc[]\n```\n"
    expanded = MemoAdocIncludes.new(memo: @memo, docs_root: @docs_root).expand(body)

    assert_includes expanded, "include::child.adoc[]"
    assert_not_includes expanded, "Child body."
  end

  test "rejects path outside docs jail" do
    body = "include::../../config/application.rb[]\n"
    expanded = MemoAdocIncludes.new(memo: @memo, docs_root: @docs_root).expand(body)

    assert_includes expanded, "include not found"
  end

  test "warns on remote include" do
    body = "include::https://example.com/x.adoc[]\n"
    expanded = MemoAdocIncludes.new(memo: @memo, docs_root: @docs_root).expand(body)

    assert_includes expanded, "remote include not supported"
  end
end
