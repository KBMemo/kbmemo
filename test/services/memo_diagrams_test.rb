# frozen_string_literal: true

require "test_helper"

class MemoDiagramsTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.update_columns(slug: "first-memo-#{@memo.id}", file_committed_at: Time.current)
    @repo = MemoRepository.new
  end

  test "list returns diagram sources under assets diagrams" do
    @repo.write_asset!(@memo, filename: "diagrams/a.mmd", io: StringIO.new("graph TD"))
    @repo.write_asset!(@memo, filename: "diagrams/a.svg", io: StringIO.new("<svg/>"))
    @repo.write_asset!(@memo, filename: "diagrams/b.puml", io: StringIO.new("@startuml\n@enduml"))

    listed = MemoDiagrams.list(@memo, repo: @repo)
    assert_equal %w[a.mmd b.puml], listed.map { |e| e[:diagram_key] }
    assert_equal "diagram::a.mmd[]", listed.find { |e| e[:diagram_key] == "a.mmd" }[:asciidoc]
    assert listed.find { |e| e[:diagram_key] == "a.mmd" }[:svg_exists]
    assert_not listed.find { |e| e[:diagram_key] == "b.puml" }[:svg_exists]
    assert_includes listed.first[:edit_url], "/diagrams/a.mmd/edit"
  end

  test "create writes source and svg via kroki" do
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>'
    name = "flow-#{SecureRandom.hex(4)}"
    with_stubbed_kroki(svg) do
      result = MemoDiagrams.create!(@memo, name: name, engine: :mermaid, repo: @repo)
      assert_equal "diagrams/#{name}.mmd", result[:source_relative]
      assert_equal "diagram::#{name}.mmd[]", result[:asciidoc]
      assert @repo.absolute_asset_path_for(@memo, "diagrams/#{name}.mmd").file?
      assert @repo.absolute_asset_path_for(@memo, "diagrams/#{name}.svg").file?
    end
  end
end
