# frozen_string_literal: true

require "test_helper"

class MemoRepositoryTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.assign_attributes(body: "= Repo test\n\nParagraph.", title: "Repo title", slug: "repo-slug")
    @repo = MemoRepository.new
  end

  test "relative_path_for follows slug-id rule" do
    assert_equal "repo-slug-#{@memo.id}.adoc", @repo.relative_path_for(@memo).to_s
  end

  test "relative_path_for nests under memo directory segment" do
    m = memos(:two)
    assert_equal "work/second-memo-#{m.id}.adoc", @repo.relative_path_for(m).to_s
  end

  test "relative_path_for uses memo when slug blank" do
    @memo.slug = ""
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

  test "write_and_commit! is idempotent when content unchanged" do
    @repo.write_and_commit!(@memo)
    root = @repo.root
    log1, = Open3.capture3("git", "log", "--oneline", chdir: root.to_s)

    @repo.write_and_commit!(@memo)
    log2, = Open3.capture3("git", "log", "--oneline", chdir: root.to_s)
    assert_equal log1, log2
  end
end
