# frozen_string_literal: true

require "application_system_test_case"

class MemoTemplateTest < ApplicationSystemTestCase
  setup do
    sign_in_via_browser(:one)
  end

  test "applies a template to the new memo form" do
    travel_to Time.zone.local(2026, 7, 24, 12, 0, 0) do
      visit memos_path
      click_button "Templateから作成"
      within "#memo-template-create-menu" do
        click_link memo_templates(:daily).name
      end
    end

    assert_equal "Daily 2026-07-24", find("#memo_title").value
    assert_includes find("#memo_body", visible: :all).value, "= Daily 2026-07-24"
    assert_equal(
      "diary, 2026-07-24",
      find("input[name='memo[tag_list]']", visible: :all).value
    )
    assert_text "diary"
    assert_text "2026-07-24"
  end
end
