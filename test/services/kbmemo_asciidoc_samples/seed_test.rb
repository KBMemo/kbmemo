# frozen_string_literal: true

require "test_helper"

class KbmemoAsciidocSamplesSeedTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @fixture_path = Rails.root.join("tmp", "asciidoc_samples_seed_test", "#{SecureRandom.hex(4)}.adoc")
    @fixture_path.dirname.mkpath
    File.write(@fixture_path, <<~ADOC, encoding: "UTF-8")
      = Fixture title

      // === Paragraphs ===

      // kbmemo:syntax-ref:paragraphs-lead
      [.lead]
      Lead paragraph sample.

      // === Tables ===

      // kbmemo:syntax-ref:tables-csv
      ,===
      A,B
      1,2
      ,===

      // === KBMemo extensions ===

      // kbmemo:syntax-ref:kbmemo-wiki
      Wiki link: [[demo]]
    ADOC
  end

  teardown do
    FileUtils.rm_rf(@fixture_path.dirname)
  end

  def seed(**opts)
    KbmemoAsciidocSamples::Seed.call(account: @account, fixture_path: @fixture_path, **opts)
  end

  test "creates a sample memo per QR id and excludes kbmemo-* ids" do
    result = seed

    assert_empty result.errors
    assert_equal 2, result.created
    assert_nil Memo.find_by(account_id: @account.id, title: "kbmemo-wiki")

    memo = Memo.find_by!(account_id: @account.id, title: "tables-csv")
    assert_equal "tables-csv", memo.properties.dig("asciidoc_sample", "syntax_ref_id")
    assert_includes memo.body, ",==="
    assert_includes memo.tags.map(&:name), "asciidoc"
    assert_equal :owner_read_write, memo.visibility.to_sym
  end

  test "adds samples to the AsciiDoc カバレッジ notebook" do
    seed
    notebook = Notebook.find_by!(account: @account, slug: "asciidoc_coverage")
    assert_equal "AsciiDoc カバレッジ", notebook.title

    memo = Memo.find_by!(account_id: @account.id, title: "paragraphs-lead")
    assert NotebookMemo.exists?(notebook: notebook, memo: memo)
  end

  test "rebuilds the checklist note with wiki links and excluded ids" do
    seed
    note = Memo.find_by!(account_id: @account.id, title: "AsciiDoc 記法対応ノート")

    assert_includes note.body, "* [x] [[tables-csv]]"
    assert_includes note.body, "* [x] [[paragraphs-lead]]"
    assert_includes note.body, "* [ ] kbmemo-wiki（KBMemo 拡張・別途）"
  end

  test "normalizes an existing manual sample title and does not duplicate it" do
    existing = Memo.create!(
      account: @account,
      memo_directory: MemoDirectory::UserSpace.ensure_subdirectory!(@account, "asciidoc", bucket: "public"),
      title: "paragraphs-lead (AsciiDoc 記法チェック)",
      title_manual: true,
      body: "= existing\n\nhand authored\n",
      visibility: :owner_read_write
    )

    result = seed

    assert_equal 1, result.created
    assert_equal 1, result.updated
    existing.reload
    assert_equal "paragraphs-lead", existing.title
    assert_equal "paragraphs-lead", existing.properties.dig("asciidoc_sample", "syntax_ref_id")
    assert_includes existing.body, "hand authored"
    assert_equal 1, Memo.where(account_id: @account.id, title: "paragraphs-lead").count
  end

  test "is idempotent on a second run" do
    seed
    result = seed

    assert_equal 0, result.created
    assert_equal 2, result.updated
    assert_equal 0, result.notebook_added
  end
end
