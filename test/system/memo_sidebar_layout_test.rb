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

  test "keeps directory tree and memo list heights stable while toggling a branch" do
    directory = memo_directories(:work)
    20.times do |i|
      MemoDirectory.create!(
        parent: directory,
        path_segment: "tree-scroll-#{i}",
        label: "Tree scroll #{i}"
      )
      Memo.create!(
        title: "List scroll memo #{i}",
        body: "body",
        memo_directory: directory,
        account: accounts(:one),
        file_committed_at: Time.current
      )
    end

    visit memos_path(sidebar_view: "directory", memo_directory_id: directory.id)

    dimensions_before = page.evaluate_script(<<~JS)
      (() => {
        const tree = document.querySelector(".kb-memo-directory-tree-scroll")
        const list = document.querySelector("#memo_sidebar_memo_list_scroll")
        return {
          treeHeight: tree.clientHeight,
          treeScrollHeight: tree.scrollHeight,
          treeOverflow: getComputedStyle(tree).overflowY,
          listHeight: list.clientHeight,
          listOverflow: getComputedStyle(list).overflowY
        }
      })()
    JS

    find(
      "[data-memo-directory-nav-branch][data-memo-directory-id='#{directory.id}'] > " \
      "button.memo-directory-nav-summary"
    ).click

    dimensions_after = page.evaluate_script(<<~JS)
      (() => {
        const tree = document.querySelector(".kb-memo-directory-tree-scroll")
        const list = document.querySelector("#memo_sidebar_memo_list_scroll")
        return {
          treeHeight: tree.clientHeight,
          treeScrollHeight: tree.scrollHeight,
          listHeight: list.clientHeight
        }
      })()
    JS

    assert_equal "auto", dimensions_before["treeOverflow"]
    assert_equal "auto", dimensions_before["listOverflow"]
    assert_equal dimensions_before["treeHeight"], dimensions_after["treeHeight"]
    assert_equal dimensions_before["listHeight"], dimensions_after["listHeight"]
    assert_not_equal dimensions_before["treeScrollHeight"], dimensions_after["treeScrollHeight"]
  end

  test "scrolls the directory tree to a manually entered directory" do
    parent = memo_directories(:work)
    directories = 20.times.map do |i|
      MemoDirectory.create!(
        parent: parent,
        path_segment: "manual-scroll-#{i}",
        label: "Manual scroll #{i}"
      )
    end
    selected = directories.last

    visit memos_path(sidebar_view: "directory", memo_directory_id: parent.id)
    fill_in "選択ディレクトリ", with: "/#{selected.full_path}"
    click_button "移動"

    assert_current_path memos_path, ignore_query: true
    query = Rack::Utils.parse_nested_query(URI.parse(page.current_url).query)
    assert_equal "directory", query["sidebar_view"]
    assert_equal "/#{selected.full_path}", query["memo_directory_path"]
    assert_selector(".kb-memo-directory-tree-scroll .kb-sidebar-nav.is-active", text: selected.display_name)
    assert_selector(".kb-memo-directory-tree-scroll[data-selected-directory-scrolled='true']")
    tree_state = page.evaluate_script(<<~JS)
      (() => {
        const tree = document.querySelector(".kb-memo-directory-tree-scroll")
        const selected = tree.querySelector(".kb-sidebar-nav.is-active")
        const treeRect = tree.getBoundingClientRect()
        const selectedRect = selected.getBoundingClientRect()
        return {
          scrollTop: tree.scrollTop,
          selectedVisible:
            selectedRect.top >= treeRect.top &&
            selectedRect.bottom <= treeRect.bottom
        }
      })()
    JS

    assert_operator tree_state["scrollTop"], :>, 0
    assert tree_state["selectedVisible"]
  end
end
