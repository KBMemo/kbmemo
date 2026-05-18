# frozen_string_literal: true

require "test_helper"

class MemoDiagramMacroTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.update_columns(slug: "first-memo-#{@memo.id}", file_committed_at: Time.current)
    @repo = MemoRepository.new
  end

  test "substitutes diagram macro to image when svg exists" do
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD\nA-->B"))
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"/>'))
    svg_path = @repo.absolute_asset_path_for(@memo, "diagrams/flow.svg")
    assert svg_path.file?, "expected #{svg_path}"

    out = MemoDiagramMacro.new(memo: @memo, repo: @repo).substitute("diagram::flow.mmd[]\n")
    assert_equal "image::diagrams/flow.svg[opts=interactive]\n", out
  end

  test "missing svg becomes admonition-like marker" do
    out = MemoDiagramMacro.new(memo: @memo, repo: @repo).substitute("diagram::missing.mmd[]\n")
    assert_includes out, "memo-diagram-missing"
    assert_includes out, "diagrams/missing.mmd"
  end
end
