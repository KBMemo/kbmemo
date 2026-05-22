# frozen_string_literal: true

require "test_helper"

class MemosControllerChecklistTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(:one)
    @memo = memos(:one)
    @memo.update_columns(
      body: <<~ADOC.strip,
        [%interactive]
        * [ ] TODO1
        * [x] TODO2
      ADOC
      properties: {}
    )
    MemoChecklist.sync_properties_from_body!(@memo)
    @memo.save!
  end

  test "draft save syncs checkboxes from body" do
    patch draft_memo_path(@memo),
      params: {
        memo: {
          body: <<~ADOC.strip,
            [%interactive]
            * [x] Renamed
            * [ ] TODO2 #cb-2
          ADOC
          properties_yaml: "other: 1\n"
        }
      },
      as: :json

    assert_response :success
    @memo.reload
    assert_equal "Renamed", @memo.properties["checkboxes"].first["label"]
    assert @memo.properties["checkboxes"].first["checked"]
    assert_equal({ "other" => 1 }, @memo.properties.except("checkboxes"))
  end

  test "checklist_toggle updates memo and returns turbo stream" do
    id = @memo.properties["checkboxes"].first["id"]

    patch checklist_toggle_memo_path(@memo),
      params: { checklist_id: id, checked: true },
      headers: { Accept: "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    @memo.reload
    assert @memo.properties["checkboxes"].find { |r| r["id"] == id }["checked"]
    assert_includes @memo.body, "* [x] TODO1"
    assert_not_includes @memo.body, "##{id}"
  end

  test "checklist_toggle turbo stream includes commit button for draft memo" do
    t = 1.hour.ago.change(usec: 0)
    @memo.update_columns(file_committed_at: t, updated_at: t)
    id = @memo.properties["checkboxes"].first["id"]

    patch checklist_toggle_memo_path(@memo),
      params: { checklist_id: id, checked: true },
      headers: { Accept: "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.body, commit_memo_path(@memo)
    assert_includes response.body, ">コミット<"
  end
end
