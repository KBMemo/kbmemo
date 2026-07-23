# frozen_string_literal: true

require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  setup do
    sign_in_via_browser(:one)
  end

  test "shows the dashboard without horizontal overflow" do
    visit root_path

    assert_text "最新のメモ"
    assert_text "タスク"
    assert_text "予定"
    assert_text "最近編集したノートブック"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")

    page.current_window.resize_to(390, 844)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end
end
