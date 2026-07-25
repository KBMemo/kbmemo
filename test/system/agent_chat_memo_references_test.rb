# frozen_string_literal: true

require "application_system_test_case"

class AgentChatMemoReferencesTest < ApplicationSystemTestCase
  setup do
    sign_in_via_browser(:one)
  end

  test "opens a new chat with the current memo referenced" do
    memo = memos(:one)
    visit memo_path(memo)

    within "#memo_#{memo.id}" do
      click_link "AIチャット"
    end

    assert_current_path agent_chat_path(new: 1, memo_reference_id: memo.id)
    within "[data-agent-chat-target='memoReferenceList']" do
      assert_link memo.title
      link = find_link(memo.title)
      assert_equal "_blank", link[:target]
      assert_equal memo_path(memo), URI(link[:href]).path
    end
    assert_text "1 / 5"
  end

  test "persists added and removed references without sending a message" do
    conversation = accounts(:one).agent_chat_conversations.create!(
      memo_reference_ids: [ memos(:one).id ]
    )
    visit agent_chat_path(conversation_id: conversation.id)

    within "[data-agent-chat-target='memoReferenceList']" do
      assert_text memos(:one).title
      find("button[aria-label='参照メモを削除']").click
    end
    assert_selector "[data-agent-chat-target='memoReferenceList'][data-sync-state='complete']"
    assert_empty conversation.reload.memo_reference_ids

    page.refresh
    within "[data-agent-chat-target='memoReferenceList']" do
      assert_no_text memos(:one).title
    end
    assert_text "0 / 5"

    click_button "メモを参照"
    within "dialog[open]" do
      find("label", text: memos(:two).title).find("input[type='checkbox']").check
      click_button "参照に追加"
    end
    assert_selector "[data-agent-chat-target='memoReferenceList'][data-sync-state='complete']"
    assert_equal [ memos(:two).id ], conversation.reload.memo_reference_ids

    page.refresh
    within "[data-agent-chat-target='memoReferenceList']" do
      assert_link memos(:two).title
    end
    assert_text "1 / 5"
  end
end
