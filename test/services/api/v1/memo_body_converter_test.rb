# frozen_string_literal: true

require "test_helper"

class Api::V1::MemoBodyConverterTest < ActiveSupport::TestCase
  test "passes through asciidoc by default" do
    attrs = Api::V1::MemoBodyConverter.normalize!(body: "== Title\n\nBody")

    assert_equal "== Title\n\nBody", attrs[:body]
    assert_not attrs.key?(:body_format)
  end

  test "converts markdown body and append_body" do
    with_markdown_converter("== Converted\n\nText") do
      attrs = Api::V1::MemoBodyConverter.normalize!(
        body: "## Title",
        append_body: "追記",
        body_format: "markdown"
      )

      assert_equal "== Converted\n\nText", attrs[:body]
      assert_equal "== Converted\n\nText", attrs[:append_body]
    end
  end

  test "rejects unsupported body_format" do
    error = assert_raises(Api::V1::MemoBodyConverter::UnsupportedFormat) do
      Api::V1::MemoBodyConverter.normalize!(body: "x", body_format: "html")
    end

    assert_includes error.message, "body_format"
  end

  private

  def with_markdown_converter(result)
    singleton = PandocMarkdownToAsciidoc.singleton_class
    original = PandocMarkdownToAsciidoc.method(:convert)
    singleton.define_method(:convert) { |_markdown| result }
    yield
  ensure
    singleton.define_method(:convert, original)
  end
end
