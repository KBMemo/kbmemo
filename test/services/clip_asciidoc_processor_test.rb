# frozen_string_literal: true

require "test_helper"

class ClipAsciidocProcessorTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
  end

  test "unwraps blockquote and converts html to asciidoc" do
    html = '<blockquote cite="https://example.com/a"><p><strong>Clip</strong></p></blockquote>'

    with_image_importer("<p><strong>Clip</strong></p>") do
      with_pandoc_convert("*Clip*") do
        result = ClipAsciidocProcessor.call(html: html, memo: @memo, source_url: "https://example.com/a")
        assert_equal "*Clip*", result
      end
    end
  end

  test "falls back to plain text wrapped in html" do
    with_image_importer("<p>Plain clip</p>") do
      with_pandoc_convert("Plain clip") do
        result = ClipAsciidocProcessor.call(html: nil, plain: "Plain clip", memo: @memo)
        assert_equal "Plain clip", result
      end
    end
  end

  private

  def with_pandoc_convert(output)
    singleton = PandocHtmlToAsciidoc.singleton_class
    original = PandocHtmlToAsciidoc.method(:convert)
    singleton.define_method(:convert) { |html| output }
    yield
  ensure
    singleton.define_method(:convert, original)
  end

  def with_image_importer(output)
    original_new = ClipImageImporter.method(:new)
    fake = Class.new do
      define_method(:initialize) { |*| }
      define_method(:localize!) { |html, **| output }
    end

    ClipImageImporter.singleton_class.define_method(:new) { |*| fake.new }
    yield
  ensure
    ClipImageImporter.singleton_class.define_method(:new, original_new)
  end
end
