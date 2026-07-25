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

  test "shows persisted image attachments after reloading a conversation" do
    conversation = accounts(:one).agent_chat_conversations.create!
    conversation.messages.create!(
      role: "user",
      content: "この画像は？",
      metadata: {
        "attachments" => [
          {
            "tsuzura_media_id" => "01JABCDEFGHJKMNPQRSTVWXYZ0",
            "filename" => "persisted-photo.jpg"
          }
        ]
      }
    )

    visit agent_chat_path(conversation_id: conversation.id)

    assert_text "この画像は？"
    assert_text "persisted-photo.jpg"

    page.refresh

    assert_text "persisted-photo.jpg"
  end

  test "adds a selected memo image to the pending chat attachments" do
    result = AgentChat::TsuzuraUpload::Result.new(
      tsuzura_media_id: "01JABCDEFGHJKMNPQRSTVWXYZ0",
      filename: "first.png"
    )
    original = AgentChat::MemoImages.method(:upload)
    AgentChat::MemoImages.define_singleton_method(:upload) do |**_kwargs|
      result
    end

    visit agent_chat_path
    click_button "メモから選ぶ"

    within "[data-agent-chat-target='memoImageResults']" do
      find("label", text: "first.png").find("input[type='checkbox']").check
    end
    click_button "添付に追加"

    assert_no_selector "dialog[data-agent-chat-target='memoImageDialog'][open]"
    within "[data-agent-chat-target='attachmentList']" do
      assert_text "first.png"
      assert_selector "button[aria-label='添付を削除']"
    end
  ensure
    AgentChat::MemoImages.define_singleton_method(:upload, original)
  end

  test "offers images from the referenced memos only" do
    visit agent_chat_path(new: 1)
    button = find_button "参照メモから選ぶ"
    assert_equal "true", button["aria-disabled"]

    visit agent_chat_path(new: 1, memo_reference_id: @first.id)
    button = find_button "参照メモから選ぶ"
    assert_equal "false", button["aria-disabled"]
    button.click

    assert_selector "[data-agent-chat-target='memoImageDialogTitle']", text: "参照メモの画像を選ぶ"
    within "[data-agent-chat-target='memoImageResults']" do
      assert_text "first.png"
      assert_no_text "second.png"
    end
  end

  test "loads the next image page while preserving selections" do
    entry_class = Struct.new(:payload) do
      def as_json
        payload
      end
    end
    build_entry = lambda do |index|
      entry_class.new(
        {
          memo_id: @first.id,
          memo_title: @first.title,
          directory: @first.memo_directory.labeled_path_from_root,
          filename: format("page-image-%02d.png", index),
          relative_path: format("page-image-%02d.png", index),
          preview_url: asset_memo_path(@first, format("page-image-%02d.png", index)),
          updated_at: @first.updated_at.iso8601
        }
      )
    end
    first_page = AgentChat::MemoImages::Page.new(
      entries: 30.times.map { |index| build_entry.call(index) },
      next_cursor: "next-page"
    )
    second_page = AgentChat::MemoImages::Page.new(
      entries: 5.times.map { |index| build_entry.call(index + 30) },
      next_cursor: nil
    )
    original = AgentChat::MemoImages.method(:list)
    AgentChat::MemoImages.define_singleton_method(:list) do |cursor:, **_kwargs|
      cursor.present? ? second_page : first_page
    end

    visit agent_chat_path
    click_button "メモから選ぶ"
    within "[data-agent-chat-target='memoImageResults']" do
      find("label", text: "page-image-00.png").find("input[type='checkbox']").check
      assert_selector "label", count: 30
    end
    click_button "さらに読み込む"

    within "[data-agent-chat-target='memoImageResults']" do
      assert_selector "label", count: 35
      assert find("label", text: "page-image-00.png").find("input[type='checkbox']").checked?
      assert_text "page-image-34.png"
    end
    assert_no_button "さらに読み込む"
  ensure
    AgentChat::MemoImages.define_singleton_method(:list, original)
  end

  private

  def prepare_memo_with_image(memo, slug:, filename:)
    memo.update_columns(slug: memo_global_slug(slug, memo), file_committed_at: Time.current)
    MemoRepository.new.write_asset!(memo, filename:, io: StringIO.new("\x89PNG\r\n\x1A\n".b))
    memo
  end
end
