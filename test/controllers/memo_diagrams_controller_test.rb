# frozen_string_literal: true

require "test_helper"

class MemoDiagramsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(:one)
    @memo = memos(:one)
    @memo.update_columns(slug: "first-memo-#{@memo.id}", file_committed_at: Time.current)
    @repo = MemoRepository.new
  end

  test "new diagram form" do
    get new_memo_diagram_path(@memo)
    assert_response :success
    assert_includes response.body, "Mermaid"
  end

  test "create redirects to edit" do
    svg = '<svg xmlns="http://www.w3.org/2000/svg"/>'
    with_stubbed_kroki(svg) do
      post memo_diagrams_path(@memo), params: { name: "arch", engine: "plantuml" }
    end
    assert_redirected_to edit_memo_diagram_path(@memo, "arch.puml")
    assert @repo.absolute_asset_path_for(@memo, "diagrams/arch.puml").file?
  end

  test "edit and update source" do
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD\nA-->B"))
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"/>'))

    get edit_memo_diagram_path(@memo, "flow.mmd")
    assert_response :success
    assert_includes response.body, "diagram::flow.mmd[]"

    svg = '<svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>'
    with_stubbed_kroki(svg) do
      patch memo_diagram_path(@memo, "flow.mmd"), params: { source: "graph TD\nX-->Y" }
    end
    assert_redirected_to edit_memo_diagram_path(@memo, "flow.mmd")
    assert_includes @repo.absolute_asset_path_for(@memo, "diagrams/flow.mmd").read, "X-->Y"
  end
end
