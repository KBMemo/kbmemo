# frozen_string_literal: true

require "application_system_test_case"

class MemoAttachmentDeleteTest < ApplicationSystemTestCase
  setup do
    @memo = memos(:one)
    @memo.update_columns(slug: memo_global_slug("first-memo", @memo), file_committed_at: Time.current)
    @repo = MemoRepository.new
    @repo.write_and_commit!(@memo)
    @repo.write_asset!(@memo, filename: "orphan.png", io: StringIO.new("\x89PNG\r\n\x1a\n"))
    sign_in_via_browser(:one)
  end

  test "deletes unreferenced attachment from panel" do
    visit edit_memo_path(@memo)

    click_on "添付ファイル"

    within "#memo-attachment-panel" do
      assert_text "orphan.png"

      accept_confirm do
        find("[data-destroy-name='orphan.png']").click
      end

      assert_no_text "orphan.png"
    end

    assert_not @repo.absolute_asset_path_for(@memo, "orphan.png").file?
  end

  test "uploads a PDF selected from the file picker" do
    file = Tempfile.new([ "memo-attachment", ".pdf" ])
    file.binmode
    file.write("%PDF-1.7\n")
    file.rewind

    visit edit_memo_path(@memo)

    find("input[data-memo-body-editor-target='attachmentInput']", visible: :all).set(file.path)

    assert_text "attachment::#{File.basename(file.path)}[]", wait: 5
    assert @repo.absolute_asset_path_for(@memo, File.basename(file.path)).file?
  ensure
    file&.close!
  end
end
