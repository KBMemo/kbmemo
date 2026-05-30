# frozen_string_literal: true

require "test_helper"

class MemoDiagramTest < ActiveSupport::TestCase
  test "source_relative_path adds diagrams prefix" do
    assert_equal "diagrams/flow.mmd", MemoDiagram.source_relative_path("flow.mmd")
    assert_equal "diagrams/flow.mmd", MemoDiagram.source_relative_path("diagrams/flow.mmd")
  end

  test "svg_relative_path swaps extension" do
    assert_equal "diagrams/flow.svg", MemoDiagram.svg_relative_path("flow.mmd")
    assert_equal "diagrams/arch.svg", MemoDiagram.svg_relative_path("diagrams/arch.puml")
  end

  test "engine_for_filename" do
    assert_equal :mermaid, MemoDiagram.engine_for_filename("a.mmd")
    assert_equal :plantuml, MemoDiagram.engine_for_filename("a.puml")
  end

  test "asciidoc_for omits diagrams prefix in macro" do
    assert_equal "diagram::flow.mmd[]", MemoDiagram.asciidoc_for("diagrams/flow.mmd")
  end

  test "normalize_source strips mermaid markdown fences" do
    fenced = <<~SRC
      ```mermaid
      sequenceDiagram
        participant ユーザー
      ```
    SRC
    out = MemoDiagram.normalize_source(:mermaid, fenced)
    assert_equal <<~SRC.strip, out
      sequenceDiagram
        participant ユーザー
    SRC
    assert_not_includes out, "```"
  end

  test "normalize_source strips plantuml markdown fences" do
    fenced = <<~SRC
      ```plantuml
      @startuml
      Alice -> Bob
      @enduml
      ```
    SRC
    out = MemoDiagram.normalize_source(:plantuml, fenced)
    assert_includes out, "@startuml"
    assert_not_includes out, "```"
  end

  test "engine_from_lang accepts svg" do
    assert_equal :svg, MemoDiagram.engine_from_lang("svg")
  end

  test "normalize_source strips svg markdown fences" do
    fenced = <<~SRC
      ```svg
      <svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>
      ```
    SRC
    out = MemoDiagram.normalize_source(:svg, fenced)
    assert_includes out, "<svg"
    assert_not_includes out, "```"
  end
end
