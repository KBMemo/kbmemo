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

  test "management menu groups admin links" do
    get root_url

    assert_select "#management-menu" do
      assert_select "a[href=?]", chat_server_path, text: "Chat サーバー設定"
      assert_select "a[href=?]", nyoy_mcp_path, text: "Nyoy MCP 設定"
      assert_select "a[href=?]", tags_path, text: "タグ管理"
      assert_select "a[href=?]", memo_templates_path, text: "テンプレート管理"
      assert_select "a[href=?]", admin_root_path, text: "アカウント管理"
    end
    assert_select "header > nav > div > a[href=?]", tags_path, count: 0
  end

  test "management menu hides account management from non-admin users" do
    sign_out
    sign_in_as(:two)

    get root_url

    assert_select "#management-menu" do
      assert_select "a[href=?]", chat_server_path, text: "Chat サーバー設定"
      assert_select "a[href=?]", nyoy_mcp_path, text: "Nyoy MCP 設定"
      assert_select "a[href=?]", tags_path, text: "タグ管理"
      assert_select "a[href=?]", memo_templates_path, text: "テンプレート管理"
      assert_select "a[href=?]", admin_root_path, count: 0
    end
  end

  test "root requires authentication" do
    sign_out

    get root_url

    assert_response :redirect
    assert_includes response.location, "/login"
  end
end
