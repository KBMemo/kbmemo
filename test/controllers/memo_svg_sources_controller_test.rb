# frozen_string_literal: true

require "test_helper"

class MemoSvgSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @memo = memos(:one)
    @memo.update!(body: <<~ADOC)
      [source,svg]
      ----
      <svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>
      ----
    ADOC
  end

  test "edit renders svg editor for authorized user" do
    sign_in_as(:one)
    get edit_svg_source_memo_url(@memo, 0)
    assert_response :success
    assert_includes response.body, 'data-controller="memo-svg-editor"'
    assert_match(/circle/, response.body)
  end

  test "edit requires sign in" do
    post "/logout"
    get edit_svg_source_memo_url(@memo, 0)
    assert_response :redirect
  end

  test "update replaces svg source in memo body" do
    sign_in_as(:one)
    updated = <<~SVG.strip
      <svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>
    SVG

    patch svg_source_memo_url(@memo, 0), params: { source: updated }
    assert_redirected_to memo_path(@memo)
    assert_includes @memo.reload.body, "<rect"
    assert_not_includes @memo.body, "<circle"
  end

  test "update rejects invalid svg" do
    sign_in_as(:one)
    patch svg_source_memo_url(@memo, 0), params: { source: "not svg" }
    assert_response :unprocessable_entity
    assert_includes @memo.reload.body, "<circle"
  end
end
