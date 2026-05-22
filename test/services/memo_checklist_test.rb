# frozen_string_literal: true

require "test_helper"

class MemoChecklistTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.update_columns(
      body: <<~ADOC.strip,
        [%interactive]
        * [ ] TODO1
        * [x] TODO2
      ADOC
      properties: {}
    )
  end

  test "sync_properties_from_body copies labels and assigns ids" do
    rows = MemoChecklist.sync_properties_from_body!(@memo)

    assert_equal 2, rows.size
    assert_equal "TODO1", rows[0]["label"]
    assert_equal false, rows[0]["checked"]
    assert_equal "TODO2", rows[1]["label"]
    assert_equal true, rows[1]["checked"]
    assert rows[0]["id"].present?
    assert_equal rows, @memo.properties["checkboxes"]
    assert_not_includes @memo.body, "##{rows[0]["id"]}"
  end

  test "toggle updates body and properties" do
    MemoChecklist.sync_properties_from_body!(@memo)
    id = @memo.properties["checkboxes"].first["id"]

    MemoChecklist.toggle!(@memo, id: id, checked: true)

    assert @memo.properties["checkboxes"].find { |r| r["id"] == id }["checked"]
    assert_includes @memo.body, "* [x] TODO1"
    assert_not_includes @memo.body, "##{id}"
  end

  test "preserves custom id suffix in body" do
    @memo.update_columns(
      body: <<~ADOC.strip,
        [%interactive]
        * [ ] Alpha #my-alpha
      ADOC
      properties: {}
    )

    rows = MemoChecklist.sync_properties_from_body!(@memo)

    assert_equal "my-alpha", rows[0]["id"]
    assert_equal "Alpha", rows[0]["label"]
  end
end
