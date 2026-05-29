# frozen_string_literal: true

require "test_helper"

class MemoSlugGitRenameTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @repo = MemoRepository.new
    @legacy_slug = "legacy-slug-#{@memo.id}"
    @memo.update_columns(
      memo_directory_id: MemoDirectory.root.id,
      slug: memo_global_slug("legacy-slug", @memo)
    )
    @memo.reload
    @target_adoc = @repo.relative_path_for(@memo).to_s
    @legacy_adoc = "#{@legacy_slug}.adoc"
    @legacy_assets = "#{@legacy_slug}.assets"
  end

  test "dry run reports rename from legacy id suffix to uid suffix" do
    write_legacy_files!

    results = renamer(dry_run: true).call
    entry = results.find { |r| r.memo_id == @memo.id }

    assert_equal :dry_run, entry.status
    assert_equal @legacy_adoc, entry.from_adoc
    assert_equal @target_adoc, entry.to_adoc
    assert_equal @legacy_assets, entry.from_assets
    assert @repo.root.join(@legacy_adoc).exist?
    assert_not @repo.root.join(@target_adoc).exist?
  end

  test "apply renames adoc and assets then optional commit" do
    write_legacy_files!

    results = renamer(dry_run: false, git_commit: true).call
    entry = results.find { |r| r.memo_id == @memo.id }

    assert_equal :renamed, entry.status
    assert_not @repo.root.join(@legacy_adoc).exist?
    assert @repo.root.join(@target_adoc).exist?
    assert @repo.root.join("#{@memo.slug}.assets/diagrams/flow.mmd").exist?

    log, err, st = Open3.capture3("git", "log", "-1", "--oneline", chdir: @repo.root.to_s)
    assert st.success?, err
    assert_includes log, "Rename memo work tree files"
  end

  test "skips when legacy path already matches uid slug" do
    @repo.write_and_commit!(@memo)

    results = renamer(dry_run: false).call
    entry = results.find { |r| r.memo_id == @memo.id }

    assert_equal :skipped, entry.status
    assert_includes entry.message, "already at uid path"
  end

  private

  def write_legacy_files!
    @repo.send(:ensure_repo!)
    @repo.root.join(@legacy_adoc).write("= Legacy\n\nBody.\n", encoding: "UTF-8")
    asset_dir = @repo.root.join(@legacy_assets, "diagrams")
    asset_dir.mkpath
    asset_dir.join("flow.mmd").write("graph TD", encoding: "UTF-8")
    Open3.capture3("git", "add", "--", @legacy_adoc, @legacy_assets, chdir: @repo.root.to_s)
    Open3.capture3(
      "git", "-c", "user.email=kbmemo@localhost", "-c", "user.name=Kbmemo",
      "commit", "-m", "legacy fixture",
      chdir: @repo.root.to_s
    )
  end

  def renamer(dry_run:, git_commit: false)
    MemoSlugGitRename.new(repo: @repo, dry_run: dry_run, git_commit: git_commit)
  end
end
