# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "root renders the signed-in dashboard" do
    get root_url

    assert_response :success
    assert_select "h1", text: "ホーム"
    assert_select "#dashboard-latest-memos", text: "最新のメモ"
    assert_select "#dashboard-tasks", text: "タスク"
    assert_select "#dashboard-schedule", text: "予定"
    assert_select "#dashboard-notebooks", text: "最近編集したノートブック"
    assert_includes response.body, memos(:one).title
    assert_includes response.body, notebooks(:one).title
  end

  test "root requires authentication" do
    sign_out

    get root_url

    assert_response :redirect
    assert_includes response.location, "/login"
  end
end
