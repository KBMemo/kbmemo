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

  test "new and edit forms use the same editor layout width" do
    visit new_memo_path
    new_width = page.evaluate_script(
      "document.querySelector('#memos_editor_scroll').getBoundingClientRect().width"
    )
    source_tab_rect = page.evaluate_script(<<~JS)
      (() => {
        const source = document.querySelector('#memo_body_editor_tab_source').getBoundingClientRect()
        const preview = document.querySelector('.memo-body-editor__preview-toggle').getBoundingClientRect()
        return { width: source.width, height: source.height, previewHeight: preview.height }
      })()
    JS
    assert_operator source_tab_rect["width"], :>=, 36
    assert_operator source_tab_rect["height"], :<, 40
    assert_in_delta source_tab_rect["previewHeight"], source_tab_rect["height"], 1

    visit edit_memo_path(memos(:one))
    edit_width = page.evaluate_script(
      "document.querySelector('#memos_editor_scroll').getBoundingClientRect().width"
    )

    assert_in_delta edit_width, new_width, 1
  end

  test "chooses whether to create another memo with the same template title" do
    travel_to Time.zone.local(2026, 7, 24, 12, 0, 0) do
      Memo.create!(
        title: "Daily 2026-07-24",
        body: "Existing",
        memo_directory: memo_directories(:work),
        account: accounts(:one)
      )

      visit new_memo_path(template_id: memo_templates(:daily).id)
      assert_text "同じタイトルのメモがあります"
      assert_link "既存のメモを開く"
      click_link "追加作成"
    end

    assert_equal "Daily 2026-07-24", find("#memo_title").value
    assert_no_text "同じタイトルのメモがあります"
  end
end
