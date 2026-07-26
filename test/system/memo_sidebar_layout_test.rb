# frozen_string_literal: true

require "application_system_test_case"

class MemoSidebarLayoutTest < ApplicationSystemTestCase
  setup do
    sign_in_via_browser(:one)
  end

  test "keeps the memo sidebar fixed while memo content scrolls independently" do
    memo = memos(:one)
    long_body = ([ "= Long memo" ] + Array.new(180, "本文をスクロールするための行です。")).join("\n\n")
    memo.update_columns(body: long_body)

    visit memo_path(memo)

    layout = page.evaluate_script(<<~JS)
      (() => {
        const header = document.querySelector(".kb-chrome-header").getBoundingClientRect()
        const sidebar = document.querySelector("#memo_sidebar_shell").getBoundingClientRect()
        const content = document.querySelector("#memos_editor_scroll")
        const sidebarScroll = document.querySelector("#memo_sidebar_memo_list_scroll")
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
    page.execute_script("document.querySelector('#memos_editor_scroll').scrollTop = 600")
    scrolled = page.evaluate_script(<<~JS)
      (() => ({
        pageScroll: window.scrollY,
        contentScroll: document.querySelector("#memos_editor_scroll").scrollTop,
        sidebarTop: document.querySelector("#memo_sidebar_shell").getBoundingClientRect().top
      }))()
    JS

    assert_equal 0, scrolled["pageScroll"]
    assert_operator scrolled["contentScroll"], :>, 0
    assert_in_delta sidebar_top_before, scrolled["sidebarTop"], 1
  end

  test "keeps normal document scrolling on mobile" do
    page.current_window.resize_to(390, 844)
    memo = memos(:one)
    long_body = ([ "= Long memo" ] + Array.new(120, "モバイルでページをスクロールするための行です。")).join("\n\n")
    memo.update_columns(body: long_body)

    visit memo_path(memo)

    layout = page.evaluate_script(<<~JS)
      (() => ({
        bodyOverflow: getComputedStyle(document.body).overflow,
        bodyHeight: document.body.scrollHeight,
        viewportHeight: window.innerHeight,
        contentOverflow: getComputedStyle(document.querySelector("#memos_editor_scroll")).overflowY
      }))()
    JS

    assert_equal "visible", layout["bodyOverflow"]
    assert_operator layout["bodyHeight"], :>, layout["viewportHeight"]
    assert_equal "visible", layout["contentOverflow"]
  ensure
    page.current_window.resize_to(1400, 1400)
  end
end
