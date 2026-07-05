# frozen_string_literal: true

require "test_helper"

class MemoRepositoryTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.assign_attributes(body: "= Repo test\n\nParagraph.", title: "Repo title", slug: "repo-slug")
    @repo = MemoRepository.new
  end

  test "relative_path_for in root directory is slug-uid filename only" do
    @memo.memo_directory = MemoDirectory.root
    @memo.slug = memo_global_slug("repo-slug", @memo)
    assert_equal "#{@memo.slug}.adoc", @repo.relative_path_for(@memo).to_s
  end

  test "relative_path_for nests under memo directory segment" do
    m = memos(:two)
    assert_equal "home/u-1/work/#{m.slug}.adoc", @repo.relative_path_for(m).to_s
  end

  test "relative_path_for uses memo when slug blank" do
    @memo.memo_directory = MemoDirectory.root
    @memo.slug = ""
    fallback = "memo-#{Memo.slug_suffix_for(@memo.uid)}"
    assert_equal "#{fallback}.adoc", @repo.relative_path_for(@memo).to_s
    @memo.slug = fallback
    assert_equal "#{fallback}.adoc", @repo.relative_path_for(@memo).to_s
  end

  test "file_contents_for includes yaml front matter and body" do
    text = @repo.file_contents_for(@memo)
    assert_includes text, "---\n"
    assert_includes text, "Repo title"
    assert_includes text, "Ideas"
    assert_includes text, "= Repo test"
  end

  test "write_and_commit! creates repo file and git commit" do
    @repo.write_and_commit!(@memo)
    path = @repo.absolute_path_for(@memo)
    assert path.exist?, "expected #{path} to exist"
    assert_includes path.read, "= Repo test"

    log, err, st = Open3.capture3("git", "log", "-1", "--oneline", chdir: @repo.root.to_s)
    assert st.success?, err
    assert_includes log, "Update memo"
  end

  test "assets_dir_relative_for is sibling of adoc file" do
    @memo.memo_directory = MemoDirectory.root
    @memo.slug = memo_global_slug("repo-slug", @memo)
    assert_equal "#{@memo.slug}.assets", @repo.assets_dir_relative_for(@memo).to_s
  end

  test "write_and_commit! includes nested assets in git commit" do
    @memo.memo_directory = MemoDirectory.root
    @memo.slug = memo_global_slug("repo-slug", @memo)
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD"))
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new("<svg/>"))
    @repo.write_and_commit!(@memo)

    assets_rel = @repo.assets_dir_relative_for(@memo)
    tracked, err, st = Open3.capture3(
      "git", "ls-files", "--",
      "#{assets_rel}/diagrams/flow.mmd",
      "#{assets_rel}/diagrams/flow.svg",
      chdir: @repo.root.to_s
    )
    assert st.success?, err
    assert_includes tracked, "flow.mmd"
    assert_includes tracked, "flow.svg"
  end

  test "write_and_commit! includes assets in git commit" do
    @memo.memo_directory = MemoDirectory.root
    @memo.slug = memo_global_slug("repo-slug", @memo)
    @repo.write_asset!(@memo, filename: "fig.png", io: StringIO.new("PNG"))
    @repo.write_and_commit!(@memo)

    asset_path = @repo.absolute_asset_path_for(@memo, "fig.png")
    assert asset_path.exist?

    tracked, err, st = Open3.capture3(
      "git", "ls-files", "--", asset_path.relative_path_from(@repo.root).to_s,
      chdir: @repo.root.to_s
    )
    assert st.success?, err
    assert_includes tracked, "fig.png"
  end

  test "relocate_memo_paths moves adoc and assets together" do
    @memo.memo_directory = memo_directories(:work)
    @repo.write_and_commit!(@memo)
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new("<svg/>"))
    old_rel = @repo.relative_path_for(@memo)
    old_assets = @repo.assets_dir_relative_for(@memo)

    @memo.memo_directory = memo_directories(:home_u_one)
    @repo.relocate_memo_paths!(@memo, from_relative: old_rel, from_assets_relative: old_assets)

    assert_not @repo.root.join(old_rel).exist?
    assert_not @repo.root.join(old_assets).exist?
    assert @repo.root.join(@repo.relative_path_for(@memo)).exist?
    assert @repo.root.join(@repo.assets_dir_relative_for(@memo), "diagrams/flow.svg").exist?
  end

  test "repair_orphaned_assets_for finds assets left at old directory" do
    @memo.memo_directory = memo_directories(:work)
    @repo.write_and_commit!(@memo)
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new("<svg/>"))
    old_assets = @repo.assets_dir_relative_for(@memo).to_s
    old_adoc = @repo.relative_path_for(@memo).to_s

    @memo.memo_directory = memo_directories(:home_u_one)
    @repo.relocate_path!(from_relative: old_adoc, to_relative: @repo.relative_path_for(@memo))

    assert @repo.repair_orphaned_assets_for!(@memo)
    assert @repo.root.join(@repo.assets_dir_relative_for(@memo), "diagrams/flow.svg").exist?
    assert_not @repo.root.join(old_assets).exist?
  end

  test "write_and_commit! is idempotent when content unchanged" do
    @repo.write_and_commit!(@memo)
    root = @repo.root
    log1, = Open3.capture3("git", "log", "--oneline", chdir: root.to_s)

    @repo.write_and_commit!(@memo)
    log2, = Open3.capture3("git", "log", "--oneline", chdir: root.to_s)
    assert_equal log1, log2
  end

  test "read_committed_snapshot! reads body and metadata from git HEAD" do
    memo = memos(:two)
    slug = memo_global_slug("committed-slug", memo)
    memo.assign_attributes(
      body: "= Committed title\n\nCommitted body.",
      title: "Committed title",
      slug: slug
    )
    @repo.write_and_commit!(memo)

    memo.assign_attributes(body: "= Draft\n\nChanged.", title: "Draft")
    snapshot = @repo.read_committed_snapshot!(memo)

    assert_includes snapshot[:body], "Committed body."
    assert_equal "Committed title", snapshot[:title]
    assert_equal slug, snapshot[:slug]
    assert_equal memo.memo_directory, snapshot[:memo_directory]
    assert_includes snapshot[:file_content], "Committed title"
  end

  test "read_committed_snapshot! finds legacy id-suffixed git paths" do
    memo = memos(:two)
    legacy_slug = "legacy-slug-#{memo.id}"
    memo.assign_attributes(
      body: "= Legacy\n\nBody.",
      title: "Legacy",
      slug: legacy_slug
    )
    @repo.write_and_commit!(memo)

    memo.assign_attributes(slug: memo_global_slug("legacy-slug", memo))
    snapshot = @repo.read_committed_snapshot!(memo)

    assert_equal legacy_slug, snapshot[:slug]
    assert_includes snapshot[:body], "Body."
  end

  test "write_work_tree_file! writes without creating git commit" do
    @repo.write_and_commit!(@memo)
    log_before, = Open3.capture3("git", "rev-list", "--count", "HEAD", chdir: @repo.root.to_s)
    @memo.assign_attributes(body: "= Work tree\n\nOnly.", slug: memo_global_slug("work-tree", @memo))
    @repo.write_work_tree_file!(@memo)
    path = @repo.absolute_path_for(@memo)
    assert path.exist?
    assert_includes path.read, "Work tree"

    log_after, = Open3.capture3("git", "rev-list", "--count", "HEAD", chdir: @repo.root.to_s)
    assert_equal log_before, log_after
  end
end
