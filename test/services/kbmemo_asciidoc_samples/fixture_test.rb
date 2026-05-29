# frozen_string_literal: true

require "test_helper"

class KbmemoAsciidocSamplesFixtureTest < ActiveSupport::TestCase
  CONTENT = <<~ADOC
    = Title line is ignored by the parser

    // kbmemo:syntax-ref:document-header
    Intro line.

    // === Paragraphs ===

    // kbmemo:syntax-ref:paragraphs
    First paragraph.

    Second paragraph.

    // kbmemo:syntax-ref:comments
    // A single-line comment

    ////
    A multi-line comment.
    ////

    // === KBMemo extensions ===

    // kbmemo:syntax-ref:kbmemo-wiki
    Wiki link: [[demo]]
  ADOC

  def entries
    KbmemoAsciidocSamples::Fixture.new(CONTENT).entries
  end

  test "splits by syntax-ref markers and preserves order" do
    assert_equal %w[document-header paragraphs comments kbmemo-wiki],
      entries.map(&:syntax_ref_id)
  end

  test "assigns categories from === headers and defaults before first header" do
    by_id = entries.index_by(&:syntax_ref_id)
    assert_equal "Document", by_id["document-header"].category
    assert_equal "Paragraphs", by_id["paragraphs"].category
    assert_equal "KBMemo extensions", by_id["kbmemo-wiki"].category
  end

  test "keeps blank lines inside a snippet but trims surrounding blanks" do
    body = entries.find { |e| e.syntax_ref_id == "paragraphs" }.body
    assert_equal "First paragraph.\n\nSecond paragraph.", body
  end

  test "preserves comment lines that are themselves the sample content" do
    body = entries.find { |e| e.syntax_ref_id == "comments" }.body
    assert_includes body, "// A single-line comment"
    assert_includes body, "////"
    refute_includes body, "=== Paragraphs ==="
  end

  test "loads the canonical repository fixture with all syntax-ref ids" do
    ids = KbmemoAsciidocSamples::Fixture.load.map(&:syntax_ref_id)
    assert_equal 76, ids.size
    assert_equal ids.uniq, ids
    assert_includes ids, "tables-csv"
    assert_includes ids, "kbmemo-math"
  end
end
