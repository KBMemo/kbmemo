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
end
