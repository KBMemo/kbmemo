# frozen_string_literal: true

require "test_helper"

class MemoWikiLinksTest < ActiveSupport::TestCase
  setup do
    @one = memos(:one)
    @two = memos(:two)
    @scope = Memo.where(id: [@one.id, @two.id])
  end

  test "substitute resolves title in same directory to asciidoc link" do
    body = "See [[Second memo]] for details."
    out = linker(source: @one).substitute(body)
    assert_equal "See link:/memos/#{@two.id}[Second memo] for details.", out
  end

  test "substitute supports custom label" do
    body = "Go to [[Second memo|the other note]]."
    out = linker(source: @one).substitute(body)
    assert_equal "Go to link:/memos/#{@two.id}[the other note].", out
  end

  test "substitute resolves global slug and displays title" do
    body = "Ref [[#{@two.slug}]]"
    out = linker(source: @one).substitute(body)
    assert_equal "Ref link:/memos/#{@two.id}[#{@two.title}]", out
  end

  test "substitute resolves legacy stem slug without id suffix" do
    body = "Ref [[second-memo]]"
    out = linker(source: @one).substitute(body)
    assert_equal "Ref link:/memos/#{@two.id}[#{@two.title}]", out
  end

  test "substitute slug link allows custom label override" do
    body = "[[#{@two.slug}|short]]"
    out = linker(source: @one).substitute(body)
    assert_equal "link:/memos/#{@two.id}[short]", out
  end

  test "substitute title match is case insensitive" do
    body = "[[SECOND MEMO]]"
    out = linker(source: @one).substitute(body)
    assert_equal "link:/memos/#{@two.id}[SECOND MEMO]", out
  end

  test "substitute unique title in scope when source directory differs" do
    other_dir = memo_directories(:home)
    @two.update_columns(memo_directory_id: other_dir.id, title: "Lonely target")
    body = "[[Lonely target]]"
    out = linker(source: @one).substitute(body)
    assert_equal "link:/memos/#{@two.id}[Lonely target]", out
  end

  test "substitute broken link when ambiguous title" do
    @two.update_columns(title: @one.title)

    body = "[[#{@one.title}]]"
    out = linker(source: @one).substitute(body)
    assert_includes out, "memo-wiki-broken"
    assert_includes out, @one.title
    assert_not_includes out, "link:/memos/"
  end

  test "substitute broken link when target not in scope" do
    body = "[[Missing memo]]"
    out = linker(source: @one).substitute(body)
    assert_includes out, "memo-wiki-broken"
    assert_includes out, "Missing memo"
  end

  test "substitute resolves directory full_path and slug" do
    work = memo_directories(:work)
    @two.update_columns(memo_directory_id: work.id)
    body = "[[#{work.full_path}/#{@two.slug}]]"
    out = linker(source: @one).substitute(body)
    assert_equal "link:/memos/#{@two.id}[#{@two.title}]", out
  end

  test "substitute directory full_path slug allows leading slash" do
    work = memo_directories(:work)
    @two.update_columns(memo_directory_id: work.id)
    body = "[[/#{work.full_path}/#{@two.slug}]]"
    out = linker(source: @one).substitute(body)
    assert_equal "link:/memos/#{@two.id}[#{@two.title}]", out
  end

  test "substitute directory full_path slug is case insensitive for path" do
    work = memo_directories(:work)
    @two.update_columns(memo_directory_id: work.id)
    body = "[[HOME/U-1/WORK/#{@two.slug}]]"
    out = linker(source: @one).substitute(body)
    assert_equal "link:/memos/#{@two.id}[#{@two.title}]", out
  end

  test "substitute directory full_path slug supports custom label" do
    work = memo_directories(:work)
    @two.update_columns(memo_directory_id: work.id)
    body = "[[#{work.full_path}/#{@two.slug}|note]]"
    out = linker(source: @one).substitute(body)
    assert_equal "link:/memos/#{@two.id}[note]", out
  end

  test "substitute broken link for unknown directory path slug" do
    body = "[[home/u-1/nope/unknown-slug-999999999]]"
    out = linker(source: @one).substitute(body)
    assert_includes out, "memo-wiki-broken"
    assert_not_includes out, "link:/memos/"
  end

  test "substitute skips fenced code blocks" do
    body = <<~BODY
      ```asciidoc
      [[Second memo]]
      ```
      [[Second memo]]
    BODY
    out = linker(source: @one).substitute(body)
    assert_includes out, "```asciidoc\n[[Second memo]]\n```"
    assert_includes out, "link:/memos/#{@two.id}[Second memo]"
    assert_equal 1, out.scan("link:/memos/").size
  end

  private

  def linker(source:, scope: @scope)
    MemoWikiLinks.new(scope: scope, source_memo: source)
  end
end
