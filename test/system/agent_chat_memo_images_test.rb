# frozen_string_literal: true

require "application_system_test_case"

class AgentChatMemoImagesTest < ApplicationSystemTestCase
  setup do
    sign_in_via_browser(:one)
    @first = prepare_memo_with_image(memos(:one), slug: "first-image", filename: "first.png")
    @second = prepare_memo_with_image(memos(:two), slug: "second-image", filename: "second.png")
  end

  test "keeps selected images while filtering memo search results" do
    visit agent_chat_path
    click_button "メモから選ぶ"

    within "[data-agent-chat-target='memoImageResults']" do
      find("label", text: "first.png").find("input[type='checkbox']").check
    end
    assert_text "1件選択中です。検索条件を変えて追加できます。"

    fill_in "メモを検索", with: @second.title
    within "[data-agent-chat-target='memoImageResults']" do
      assert_selector "label", text: "second.png"
      find("label", text: "second.png").find("input[type='checkbox']").check
    end
    assert_text "2件選択中です。検索条件を変えて追加できます。"

    fill_in "メモを検索", with: ""
    within "[data-agent-chat-target='memoImageResults']" do
      assert find("label", text: "first.png").find("input[type='checkbox']").checked?
      assert find("label", text: "second.png").find("input[type='checkbox']").checked?
    end
  end

  private

  def prepare_memo_with_image(memo, slug:, filename:)
    memo.update_columns(slug: memo_global_slug(slug, memo), file_committed_at: Time.current)
    MemoRepository.new.write_asset!(memo, filename:, io: StringIO.new("\x89PNG\r\n\x1A\n".b))
    memo
  end
end
