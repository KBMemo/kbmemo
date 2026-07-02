# frozen_string_literal: true

require "test_helper"

class PandocMarkdownToAsciidocTest < ActiveSupport::TestCase
  setup do
    skip "pandoc が必要です" unless pandoc_available?
  end

  test "converts markdown heading and list to asciidoc" do
    markdown = <<~MD
      ## Hello

      - first
      - **second**
    MD

    adoc = PandocMarkdownToAsciidoc.convert(markdown)

    assert_includes adoc, "Hello"
    assert_includes adoc, "* first"
    assert_includes adoc, "*second*"
  end

  private

  def pandoc_available?
    PandocRunner.pandoc_path.present?
  end
end
