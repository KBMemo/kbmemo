# frozen_string_literal: true

require "test_helper"

class MemoRepositoryTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.assign_attributes(body: "= Repo test\n\nParagraph.", title: "Repo title", slug: "repo-slug")
    @repo = MemoRepository.new
  end

  test "relative_path_for in root directory is slug-id filename only" do
    @memo.memo_directory = MemoDirectory.root
    @memo.slug = "repo-slug-#{@memo.id}"
    assert_equal "repo-slug-#{@memo.id}.adoc", @repo.relative_path_for(@memo).to_s
  end

  test "relative_path_for nests under memo directory segment" do
    m = memos(:two)
    assert_equal "home/u-1/work/#{m.slug}.adoc", @repo.relative_path_for(m).to_s
  end

  test "relative_path_for uses memo when slug blank" do
    @memo.memo_directory = MemoDirectory.root
    @memo.slug = ""
    assert_equal "memo-#{@memo.id}.adoc", @repo.relative_path_for(@memo).to_s
    @memo.slug = "memo-#{@memo.id}"
    assert_equal "memo-#{@memo.id}.adoc", @repo.relative_path_for(@memo).to_s
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
    @memo.slug = "repo-slug-#{@memo.id}"
    assert_equal "repo-slug-#{@memo.id}.assets", @repo.assets_dir_relative_for(@memo).to_s
  end

  test "write_and_commit! includes nested assets in git commit" do
    @memo.memo_directory = MemoDirectory.root
    @memo.slug = "repo-slug-#{@memo.id}"
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
    @memo.slug = "repo-slug-#{@memo.id}"
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

  test "write_and_commit! is idempotent when content unchanged" do
    @repo.write_and_commit!(@memo)
    root = @repo.root
    log1, = Open3.capture3("git", "log", "--oneline", chdir: root.to_s)

    @repo.write_and_commit!(@memo)
    log2, = Open3.capture3("git", "log", "--oneline", chdir: root.to_s)
    assert_equal log1, log2
  end
end
