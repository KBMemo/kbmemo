# frozen_string_literal: true

require "application_system_test_case"

class NotebookSidebarLayoutTest < ApplicationSystemTestCase
  setup do
    sign_in_via_browser(:one)
  end

  test "keeps the full-height sidebar while notebook content scrolls independently" do
    notebook = notebooks(:one)
    entry = notebook_memos(:one_one)
    long_body = ([ "= Long memo" ] + Array.new(180, "本文をスクロールするための行です。")).join("\n\n")
    entry.memo.update_columns(body: long_body)

    visit notebook_path(notebook, memo_id: entry.memo_id)

    layout = page.evaluate_script(<<~JS)
      (() => {
        const header = document.querySelector(".kb-chrome-header").getBoundingClientRect()
        const sidebar = document.querySelector("#notebook_sidebar_shell").getBoundingClientRect()
        const content = document.querySelector("#notebook_memo_panel")
        const sidebarScroll = document.querySelector(".kb-notebook-sidebar-scroll")
        return {
          viewportHeight: window.innerHeight,
          headerBottom: header.bottom,
          sidebarTop: sidebar.top,
          sidebarBottom: sidebar.bottom,
          contentOverflow: getComputedStyle(content).overflowY,
          sidebarOverflow: getComputedStyle(sidebarScroll).overflowY,
          contentScrollable: content.scrollHeight > content.clientHeight
        }
      })()
    JS

    assert_in_delta layout["headerBottom"], layout["sidebarTop"], 2
    assert_in_delta layout["viewportHeight"], layout["sidebarBottom"], 2
    assert_equal "auto", layout["contentOverflow"]
    assert_equal "auto", layout["sidebarOverflow"]
    assert layout["contentScrollable"]

    sidebar_top_before = layout["sidebarTop"]
    page.execute_script("document.querySelector('#notebook_memo_panel').scrollTop = 600")
    scrolled = page.evaluate_script(<<~JS)
      (() => ({
        pageScroll: window.scrollY,
        contentScroll: document.querySelector("#notebook_memo_panel").scrollTop,
        sidebarTop: document.querySelector("#notebook_sidebar_shell").getBoundingClientRect().top
      }))()
    JS

    assert_equal 0, scrolled["pageScroll"]
    assert_operator scrolled["contentScroll"], :>, 0
    assert_in_delta sidebar_top_before, scrolled["sidebarTop"], 1
  end

  test "keeps the normal document flow on mobile" do
    page.current_window.resize_to(390, 844)
    notebook = notebooks(:one)
    entry = notebook_memos(:one_one)
    long_body = ([ "= Long memo" ] + Array.new(120, "モバイルでページをスクロールするための行です。")).join("\n\n")
    entry.memo.update_columns(body: long_body)

    visit notebook_path(notebook, memo_id: entry.memo_id)

    layout = page.evaluate_script(<<~JS)
      (() => ({
        bodyOverflow: getComputedStyle(document.body).overflow,
        bodyHeight: document.body.scrollHeight,
        viewportHeight: window.innerHeight,
        contentOverflow: getComputedStyle(document.querySelector("#notebook_memo_panel")).overflowY
      }))()
    JS

    assert_equal "visible", layout["bodyOverflow"]
    assert_operator layout["bodyHeight"], :>, layout["viewportHeight"]
    assert_equal "visible", layout["contentOverflow"]
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "searches for an existing memo and adds it to the selected hierarchy" do
    notebook = notebooks(:one)
    parent = notebook_memos(:one_one)
    sibling = notebook_memos(:one_two)
    sibling.update!(parent: parent)
    memo = Memo.create!(account: accounts(:one), title: "Search target memo", body: "= Search target memo")

    visit notebook_path(notebook)
    search_label = "「#{notebook.display_label_for_memo(parent)}」の子階層に既存メモを追加"
    parent_row = find("[data-notebook-memo-row][data-notebook-memo-id='#{parent.id}']")
    parent_row.hover
    assert_equal "1", page.evaluate_script(
      "getComputedStyle(document.querySelector('[data-notebook-memo-row][data-notebook-memo-id=\"#{parent.id}\"] .kb-notebook-tree-row-search-button')).opacity"
    )
    assert_equal "0", page.evaluate_script(
      "getComputedStyle(document.querySelector('[data-notebook-memo-row][data-notebook-memo-id=\"#{sibling.id}\"] .kb-notebook-tree-row-search-button')).opacity"
    )
    page.execute_script("document.documentElement.classList.add('notebook-memo-tree-dragging')")
    assert_equal "0", page.evaluate_script(
      "getComputedStyle(document.querySelector('[data-notebook-memo-row][data-notebook-memo-id=\"#{parent.id}\"] .kb-notebook-tree-row-search-button')).opacity"
    )
    assert_equal "none", page.evaluate_script(
      "getComputedStyle(document.querySelector('[data-notebook-memo-row][data-notebook-memo-id=\"#{parent.id}\"] .kb-notebook-tree-row-search-button')).pointerEvents"
    )
    page.execute_script("document.documentElement.classList.remove('notebook-memo-tree-dragging')")
    assert_equal "1", page.evaluate_script(
      "getComputedStyle(document.querySelector('[data-notebook-memo-row][data-notebook-memo-id=\"#{parent.id}\"] .kb-notebook-tree-row-search-button')).opacity"
    )
    search_button = parent_row.find("button[aria-label='#{search_label}']")
    icon_color = page.evaluate_script(<<~JS, search_button)
      ((button) => {
        const probe = document.createElement("span")
        probe.style.color = "var(--kb-text-secondary)"
        button.append(probe)
        const colors = {
          actual: getComputedStyle(button).color,
          expected: getComputedStyle(probe).color
        }
        probe.remove()
        return colors
      })(arguments[0])
    JS
    assert_equal icon_color["expected"], icon_color["actual"]
    search_button.click

    assert_selector "dialog#notebook_memo_picker_dialog[open]"
    within "dialog#notebook_memo_picker_dialog" do
      click_button "キャンセル"
    end
    assert_no_selector "dialog#notebook_memo_picker_dialog[open]"
    assert_equal parent.id.to_s, page.evaluate_script(
      "document.activeElement.closest('[data-notebook-memo-row]')?.dataset.notebookMemoId"
    )
    assert_equal "0", page.evaluate_script(
      "getComputedStyle(document.querySelector('[data-notebook-memo-row][data-notebook-memo-id=\"#{parent.id}\"] .kb-notebook-tree-row-search-button')).opacity"
    )

    parent_row.hover
    parent_row.find("button[aria-label='#{search_label}']").click
    fill_in "追加する既存メモを検索", with: memo.title
    find("[data-notebook-memo-picker-dialog-target='results'] button", text: memo.title).click
    within "dialog#notebook_memo_picker_dialog" do
      click_button "追加"
    end

    assert_current_path notebook_path(notebook, memo_id: memo.id)
    assert_equal parent.id, notebook.notebook_memos.find_by!(memo: memo).parent_id
  end
end
