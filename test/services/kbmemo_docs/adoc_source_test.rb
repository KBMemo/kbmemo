# frozen_string_literal: true

require "test_helper"

class KbmemoDocsAdocSourceTest < ActiveSupport::TestCase
  test "parses title from level-0 heading" do
    source = KbmemoDocs::AdocSource.new(
      relative_path: "architecture/sample.adoc",
      content: "= Sample Title\n\nBody text.\n"
    )

    assert_equal "Sample Title", source.title
    assert_equal "Body text.\n", source.body
    assert_equal "architecture-sample", source.slug_stem
    assert_includes source.path_tags, "architecture"
  end

  test "parses yaml front matter title" do
    source = KbmemoDocs::AdocSource.new(
      relative_path: "deployment/production.adoc",
      content: "---\ntitle: Production Guide\n---\n\n= Ignored\n"
    )

    assert_equal "Production Guide", source.title
    assert_equal "deployment-production", source.slug_stem
  end
end
