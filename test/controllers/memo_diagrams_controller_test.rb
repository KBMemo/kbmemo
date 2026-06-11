# frozen_string_literal: true

require "test_helper"

class MemoDiagramsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(:one)
    @memo = memos(:one)
    @memo.update_columns(slug: memo_global_slug("first-memo", @memo), file_committed_at: Time.current)
    @repo = MemoRepository.new
  end

  test "new diagram form" do
    get new_memo_diagram_path(@memo)
    assert_response :success
    assert_includes response.body, "Mermaid"
    assert_select "input#name[aria-describedby='diagram-name-help']"
    assert_select "p#diagram-name-help"
  end

  test "edit plantuml uses diagram editor with plantuml engine" do
    @repo.write_asset!(@memo, filename: "diagrams/arch.puml", io: StringIO.new("@startuml\nA -> B\n@enduml"))

    get edit_memo_diagram_path(@memo, "arch.puml")
    assert_response :success
    assert_includes response.body, 'data-memo-diagram-editor-engine-value="plantuml"'
  end

  test "create redirects to edit" do
    name = "arch-#{SecureRandom.hex(4)}"
    svg = '<svg xmlns="http://www.w3.org/2000/svg"/>'
    with_stubbed_kroki(svg) do
      post memo_diagrams_path(@memo), params: { name: name, engine: "plantuml" }
    end
    assert_redirected_to edit_memo_diagram_path(@memo, "#{name}.puml")
    assert @repo.absolute_asset_path_for(@memo, "diagrams/#{name}.puml").file?
  end

  test "edit and update source" do
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD\nA-->B"))
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"/>'))

    get edit_memo_diagram_path(@memo, "flow.mmd")
    assert_response :success
    assert_includes response.body, "diagram::flow.mmd[]"
    assert_includes response.body, 'data-controller="memo-diagram-editor"'
    assert_includes response.body, 'data-memo-diagram-editor-engine-value="mermaid"'
    assert_includes response.body, "data-memo-diagram-editor-preview-url-value"
    assert_includes response.body, 'data-memo-diagram-editor-target="preview"'
    assert_select "#diagram-source-help.sr-only"
    assert_select "#diagram-preview-loading[aria-live='polite']"
    assert_select "#diagram-preview-error[role='alert']"
    assert_select "[data-memo-diagram-editor-target='preview'][role='img'][aria-labelledby='diagram-preview-label'][aria-describedby='diagram-preview-loading diagram-preview-error']"

    svg = '<svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>'
    with_stubbed_kroki(svg) do
      patch memo_diagram_path(@memo, "flow.mmd"), params: { source: "graph TD\nX-->Y" }
    end
    assert_redirected_to edit_memo_diagram_path(@memo, "flow.mmd")
    assert_includes @repo.absolute_asset_path_for(@memo, "diagrams/flow.mmd").read, "X-->Y"
  end

  test "view shows svg viewer when svg exists" do
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD\nA-->B"))
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"/>'))

    get view_memo_diagram_path(@memo, "flow.mmd")
    assert_response :success
    assert_includes response.body, 'data-controller="diagram-svg-viewer"'
    assert_includes response.body, "/memos/#{@memo.id}/assets/diagrams/flow.svg"
    assert_includes response.body, "diagram-svg-viewer#zoomIn"
    assert_select "button[aria-label='縮小']"
    assert_select "button[aria-label='ズームを100%に戻す']"
    assert_select "button[aria-label='拡大']"
    assert_select "button[aria-label='画面に合わせる']"
  end

  test "view redirects when svg missing" do
    key = "pending-#{SecureRandom.hex(4)}.mmd"
    @repo.write_asset!(@memo, filename: "diagrams/#{key}", io: StringIO.new("graph TD\nA-->B"))

    get view_memo_diagram_path(@memo, key)
    assert_redirected_to edit_memo_diagram_path(@memo, key)
    assert_equal "SVG がまだありません。ダイアグラムを編集して保存してください。", flash[:alert]
  end

  test "source shows read-only diagram source viewer" do
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD\nA-->B"))
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"/>'))

    get source_memo_diagram_path(@memo, "flow.mmd")
    assert_response :success
    assert_includes response.body, 'data-controller="diagram-source-viewer"'
    assert_includes response.body, "graph TD"
    assert_includes response.body, 'data-diagram-source-viewer-engine-value="mermaid"'
    assert_includes response.body, "ビューアで開く"
    assert_select "label#diagram-source-viewer-label.sr-only[for='diagram_source_viewer_field']"
    assert_select "textarea#diagram_source_viewer_field[data-diagram-source-viewer-target='field']"
    assert_select "[data-diagram-source-viewer-target='host'][aria-labelledby='diagram-source-viewer-label']"
  end

  test "preview returns svg without saving source" do
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD\nA-->B"))

    svg = '<svg xmlns="http://www.w3.org/2000/svg"><text>preview</text></svg>'
    with_stubbed_kroki(svg) do
      post preview_memo_diagram_path(@memo, "flow.mmd"),
        params: { source: "graph TD\nP-->Q" },
        as: :json
    end

    assert_response :success
    assert_equal svg, response.parsed_body["svg"]
    assert_includes @repo.absolute_asset_path_for(@memo, "diagrams/flow.mmd").read, "A-->B"
  end
end
