# frozen_string_literal: true

require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  setup do
    sign_in_via_browser(:one)
  end

  test "shows the dashboard without horizontal overflow" do
    visit root_path

    assert_text "カレンダー"
    assert_text "最新のメモ"
    assert_text "カンバン"
    assert_text "予定"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    calendar_width = page.evaluate_script(
      "document.querySelector('.kb-dashboard-calendar').getBoundingClientRect().width"
    )
    assert_operator calendar_width, :<=, 352

    page.current_window.resize_to(390, 844)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end

  test "opens the management menu" do
    visit root_path

    click_button "管理"

    within "#management-menu" do
      assert_link "Chat サーバー設定"
      assert_link "Nyoy MCP 設定"
      assert_link "メモ管理"
      assert_link "タグ管理"
      assert_link "テンプレート管理"
      assert_link "アカウント管理"
    end
    assert_equal "true", find("#management-menu-trigger")["aria-expanded"]
    menu_width = page.evaluate_script(
      "document.querySelector('#management-menu').getBoundingClientRect().width"
    )
    assert_operator menu_width, :>=, 192
  end
end
