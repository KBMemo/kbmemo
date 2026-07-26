# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "root renders the signed-in dashboard" do
    get root_url

    assert_response :success
    assert_select "h1", text: "ホーム"
    assert_select "#dashboard-calendar", text: "カレンダー"
    assert_select "#dashboard-latest-memos", text: "最新のメモ"
    assert_select "#dashboard-boards", text: "カンバン"
    assert_select "#dashboard-schedule", text: "予定"
    assert_includes response.body, memos(:one).title
    assert_includes response.body, boards(:one).title
    assert_select ".kb-dashboard > .mb-6 a", text: "新規メモ", count: 0
    assert_select "section[aria-labelledby='dashboard-latest-memos']" do
      assert_select "a[href=?]", new_memo_path, text: "+新規"
      assert_select "#dashboard-template-create-trigger", text: /Templateから作成/
      assert_select "#dashboard-template-create-menu a[href=?]",
        new_memo_path(template_id: memo_templates(:daily).id),
        text: memo_templates(:daily).name
    end
    assert_select ".kb-dashboard-layout > .kb-dashboard-column", count: 2 do |columns|
      assert_select columns.first, "#dashboard-calendar"
      assert_select columns.first, "#dashboard-schedule"
      assert_select columns[1], "#dashboard-boards"
      assert_select columns[1], "#dashboard-latest-memos"
    end
  end

  test "calendar accepts a requested month and falls back for invalid input" do
    get root_url(schedule_month: "2026-05")

    assert_response :success
    assert_select "section[aria-labelledby='dashboard-calendar'] .kb-dashboard-calendar", text: /2026年5月/

    get root_url(schedule_month: "invalid")

    assert_response :success
    assert_select "section[aria-labelledby='dashboard-calendar'] .kb-dashboard-calendar",
      text: /#{Date.current.year}年#{Date.current.month}月/
  end

  test "management menu groups admin links" do
    get root_url

    assert_select "#management-menu" do
      assert_select "a[href=?]", chat_server_path, text: "Chat サーバー設定"
      assert_select "a[href=?]", nyoy_mcp_path, text: "Nyoy MCP 設定"
      assert_select "a[href=?]", manage_memos_path, text: "メモ管理"
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
      assert_select "a[href=?]", manage_memos_path, text: "メモ管理"
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
