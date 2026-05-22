# frozen_string_literal: true

require "test_helper"

class MemosHelperTest < ActionView::TestCase
  include MemosHelper
  include Pundit::Authorization

  def pundit_user
    accounts(:one)
  end

  def policy_scope(scope)
    MemoPolicy::Scope.new(pundit_user, scope).resolve
  end

  test "memo_wiki_link_reference uses global slug only" do
    memo = memos(:two)
    assert_equal "[[#{memo.slug}]]", memo_wiki_link_reference_for(memo)
  end

  test "memo_wiki_link_reference_for returns nil when slug blank" do
    memo = memos(:one)
    memo.update_columns(slug: "")
    assert_nil memo_wiki_link_reference_for(memo)
  end

  test "memo_html converts wiki link to memo href" do
    html = memo_html("See [[Second memo]].", source_memo: memos(:one))
    assert_includes html, %(href="/memos/#{memos(:two).id}")
    assert_includes html, "Second memo"
  end

  test "memo_html renders broken wiki link with styled span" do
    html = memo_html("[[no-such-memo]]", source_memo: memos(:one))
    assert_includes html, 'class="memo-wiki-broken"'
    assert_includes html, "no-such-memo"
    assert_not_includes html, "&lt;span"
  end

  test "memo_html renders fenced code as listingblock" do
    html = memo_html("```ruby\nx = 1\n```", source_memo: memos(:one))
    assert_includes html, 'class="listingblock"'
    assert_includes html, 'data-lang="ruby"'
  end

  test "memo_html renders asciidoc source block with title and language" do
    body = <<~ADOC
      .Some Ruby code
      [source,ruby]
      ----
      require 'sinatra'
      ----
    ADOC
    html = memo_html(body, source_memo: memos(:one))
    assert_includes html, 'class="listingblock"'
    assert_includes html, "Some Ruby code"
    assert_includes html, 'data-lang="ruby"'
    assert_includes html, "require 'sinatra'"
  end

  test "memo_html renders pipe table with title and columns" do
    body = <<~ADOC
      .Table 1
      [cols="2,3"]
      |===
      |A |B
      |1 |2
      |===
    ADOC
    html = memo_html(body, source_memo: memos(:one))
    assert_includes html, 'class="tableblock"'
    assert_includes html, "Table 1"
    assert_includes html, ">A<"
    assert_includes html, ">1<"
  end

  test "memo_properties_summary_line summarizes checkboxes" do
    memo = memos(:one)
    memo.update_columns(
      properties: {
        "checkboxes" => [
          { "id" => "cb-1", "label" => "TODO1", "checked" => true },
          { "id" => "cb-2", "label" => "TODO2", "checked" => false }
        ]
      }
    )

    line = memo_properties_summary_line(memo)
    assert_includes line, "checkboxes: 2件"
    assert_includes line, "cb-1"
    assert_includes line, "TODO1"
    assert_includes line, "✓"
    assert_includes line, "○"
  end

  test "memo_html adds checklist controls for interactive list" do
    memo = memos(:one)
    memo.update_columns(
      body: <<~ADOC.strip,
        [%interactive]
        * [ ] TODO1
      ADOC
      properties: {}
    )
    MemoChecklist.sync_properties_from_body!(memo)
    memo.save!

    html = memo_html(memo.body, source_memo: memo)
    assert_includes html, 'data-memo-checklist-id'
    assert_includes html, "change->memo-checklist#toggle"
  end

  test "memo_html renders diagram macro via cached svg" do
    memo = memos(:one)
    repo = MemoRepository.new
    repo.write_asset!(memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD"))
    repo.write_asset!(memo, filename: "diagrams/flow.svg", io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>'))

    html = memo_html("diagram::flow.mmd[]", source_memo: memo)
    assert_includes html, %(data="/memos/#{memo.id}/assets/diagrams/flow.svg")
    assert_includes html, "<object"
    assert_includes html, "memo-show-asset-actions"
    assert_includes html, "ビューアで開く"
    assert_includes html, %(href="/memos/#{memo.id}/diagrams/flow.mmd/view")
    assert_includes html, "ソース"
    assert_includes html, %(href="/memos/#{memo.id}/diagrams/flow.mmd/source")
  end

  test "memo_html renders stem block with title via katex" do
    body = <<~ADOC
      .stem title
      [stem]
      ++++
      E=mc^2
      ++++
    ADOC
    html = memo_html(body, source_memo: memos(:one))
    assert_includes html, 'class="katex"'
    assert_includes html, "stem title"
    assert_includes html, ">E=mc"
  end

  test "memo_html renders stem and latexmath via katex" do
    body = <<~ADOC
      Inline stem: stem:[E = mc^2]

      Display block:

      [stem]
      ++++
      \\sqrt{4}
      ++++

      latexmath:[\\int_0^1 x^2 dx]
    ADOC

    html = memo_html(body, source_memo: memos(:one))
    assert_includes html, 'class="katex"'
    assert_includes html, "katex-display"
    assert_includes html, ">E = mc"
    assert_not_includes html, "stem:[E"
  end

  test "memo_html renders svg image as img in safe mode" do
    memo = memos(:one)
    repo = MemoRepository.new
    svg = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>
    SVG
    repo.write_asset!(memo, filename: "icon.svg", io: StringIO.new(svg))

    html = memo_html("image::icon.svg[]", source_memo: memo)
    assert_includes html, %(src="/memos/#{memo.id}/assets/icon.svg")
    assert_includes html, "<img"
    assert_not_includes html, "<svg"
  end

  test "memo_html renders image with memo asset url" do
    memo = memos(:one)
    repo = MemoRepository.new
    repo.write_asset!(memo, filename: "shot.png", io: StringIO.new("PNG"))

    html = memo_html("image::shot.png[]", source_memo: memo)
    assert_includes html, %(src="/memos/#{memo.id}/assets/shot.png")
    assert_includes html, "<img"
    assert_includes html, 'loading="lazy"'
    assert_includes html, 'decoding="async"'
    assert_includes html, "ビューアで開く"
    assert_includes html, %(href="/memos/#{memo.id}/assets/shot.png/view")
  end

  test "memo_html renders admonition with font icon" do
    html = memo_html("NOTE: Remember this.", source_memo: memos(:one))
    assert_includes html, 'class="admonitionblock note"'
    assert_includes html, 'class="fa icon-note"'
  end

  test "memo_html leaves wiki syntax inside fenced code" do
    body = "```\n[[Second memo]]\n```\n\n[[Second memo]]"
    html = memo_html(body, source_memo: memos(:one))
    assert_includes html, "[[Second memo]]"
    assert_includes html, %(href="/memos/#{memos(:two).id}")
  end

  test "memo_directory_tree_select_option_pairs uses NBSP indent when excluding root" do
    dirs = [
      memo_directories(:root),
      memo_directories(:home),
      memo_directories(:home_u_one),
      memo_directories(:work)
    ]
    pairs = memo_directory_tree_select_option_pairs(dirs, exclude_root: true)
    work_id = memo_directories(:work).id
    work_label = pairs.find { |_l, id| id == work_id }&.first
    leading_nbsp = work_label[/\A\u00a0+/]
    assert leading_nbsp, "expected leading NBSP indent, got #{work_label.inspect}"
    assert_operator leading_nbsp.length, :>=, 4
  end

  test "memo_directory_tree_select_option_pairs exclude_root omits root id" do
    dirs = [memo_directories(:root), memo_directories(:home)]
    pairs = memo_directory_tree_select_option_pairs(dirs, exclude_root: true)
    assert_not_includes pairs.map(&:last), memo_directories(:root).id
    assert_includes pairs.map(&:last), memo_directories(:home).id
  end

  test "memo_directory_nav_details_open respects nav_open_directory_ids" do
    @nav_open_directory_ids = [memo_directories(:public).id]
    @current_memo_directory = memo_directories(:root)

    assert memo_directory_nav_details_open?(memo_directories(:public))
    assert_not memo_directory_nav_details_open?(memo_directories(:home))
  end

  test "memo_directory_path_from_root_label joins segment labels from root" do
    home_u_one = memo_directories(:home_u_one)
    work = memo_directories(:work)
    assert_equal "/Home/User one", memo_directory_path_from_root_label(home_u_one)
    assert_equal "/Home/User one/仕事", memo_directory_path_from_root_label(work)
    assert_equal "/", memo_directory_path_from_root_label(memo_directories(:root))
  end

  test "memo_directory_tree_select_option_pairs can label root row for parent picker" do
    dirs = [memo_directories(:root), memo_directories(:home)]
    pairs = memo_directory_tree_select_option_pairs(dirs, exclude_root: false, root_option_label: "（最上位）")
    root_id = memo_directories(:root).id
    root_label = pairs.find { |_l, id| id == root_id }&.first
    assert_equal "（最上位）", root_label
  end
end
