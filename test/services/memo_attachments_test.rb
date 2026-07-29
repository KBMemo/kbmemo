# frozen_string_literal: true

require "test_helper"

class MemoAttachmentsTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.update_columns(slug: memo_global_slug("first-memo", @memo), file_committed_at: Time.current)
    @repo = MemoRepository.new
  end

  test "list includes diagram and image with reference flags" do
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD"))
    @repo.write_asset!(@memo, filename: "orphan.png", io: StringIO.new("PNG"))
    @repo.write_asset!(@memo, filename: "used.png", io: StringIO.new("PNG"))

    body = "diagram::flow.mmd[]\nimage::used.png[]\n"
    entries = MemoAttachments.list(@memo, body: body, repo: @repo)

    diagram = entries.find { |e| e.name == "flow.mmd" }
    orphan = entries.find { |e| e.name == "orphan.png" }
    used = entries.find { |e| e.name == "used.png" }

    assert diagram
    assert diagram.referenced
    assert diagram.svg_missing
    assert_nil diagram.delete_path, "使用中のダイアグラムは削除不可"

    assert orphan
    assert_not orphan.referenced
    assert_equal "image::orphan.png[]", orphan.insert_text
    assert_equal "orphan.png", orphan.delete_path

    assert used
    assert used.referenced
    assert_nil used.delete_path, "使用中の画像は削除不可"
  end

  test "unreferenced diagram has delete path" do
    @repo.write_asset!(@memo, filename: "diagrams/orphan.mmd", io: StringIO.new("graph TD"))

    entries = MemoAttachments.list(@memo, body: "", repo: @repo)
    diagram = entries.find { |e| e.name == "orphan.mmd" }

    assert diagram
    assert_not diagram.referenced
    assert diagram.delete_path.present?
    assert_equal "diagrams/orphan.mmd", diagram.delete_path
  end

  test "companion diagram svg is not listed separately" do
    @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD"))
    @repo.write_asset!(@memo, filename: "diagrams/flow.svg", io: StringIO.new("<svg></svg>"))

    entries = MemoAttachments.list(@memo, body: "", repo: @repo)

    assert entries.any? { |e| e.name == "flow.mmd" }
    assert_not entries.any? { |e| e.relative_path == "diagrams/flow.svg" }
  end

  test "destroy path uses query param for jpeg images" do
    @repo.write_asset!(@memo, filename: "photo.jpeg", io: StringIO.new("JPEG"))

    entries = MemoAttachments.list(@memo, body: "", repo: @repo)
    image = entries.find { |e| e.name == "photo.jpeg" }

    assert image
    assert image.delete_path.present?
    assert_equal "photo.jpeg", image.delete_path
  end

  test "delete path for svg is relative path" do
    @repo.write_asset!(@memo, filename: "icon.svg", io: StringIO.new("<svg></svg>"))

    entries = MemoAttachments.list(@memo, body: "", repo: @repo)
    image = entries.find { |e| e.name == "icon.svg" }

    assert image
    assert_equal "icon.svg", image.delete_path
  end

  test "list includes document attachment with reference flag" do
    @repo.write_asset!(@memo, filename: "report.pdf", io: StringIO.new("%PDF-1.7"))

    entries = MemoAttachments.list(@memo, body: "attachment::report.pdf[]", repo: @repo)
    document = entries.find { |e| e.name == "report.pdf" }

    assert document
    assert_equal :document, document.kind
    assert document.referenced
    assert_equal "attachment::report.pdf[]", document.insert_text
    assert_nil document.delete_path
  end
end
