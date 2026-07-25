# frozen_string_literal: true

require "test_helper"

module AgentChat
  class MemoImagesTest < ActiveSupport::TestCase
    setup do
      @memo = memos(:one)
      @memo.update_columns(slug: memo_global_slug("memo-images", @memo), file_committed_at: Time.current)
      @repo = MemoRepository.new
    end

    test "lists image metadata without diagram sources" do
      @repo.write_asset!(@memo, filename: "photo.png", io: StringIO.new("PNG"))
      @repo.write_asset!(@memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD"))

      entries = MemoImages.list(scope: Memo.where(id: @memo.id), query: "", repo: @repo)

      assert_equal [ "photo.png" ], entries.map(&:relative_path)
      json = entries.first.as_json
      assert_equal @memo.id, json[:memo_id]
      assert_equal @memo.memo_directory.labeled_path_from_root, json[:directory]
      assert_equal MemoAssets.asset_url_for(@memo, "photo.png"), json[:preview_url]
    end

    test "rejects a path outside the memo assets directory" do
      assert_raises(MemoAssets::InvalidFile) do
        MemoImages.upload(
          memo: @memo,
          relative_path: "../secret.png",
          cookie_header: "",
          repo: @repo
        )
      end
    end

    test "uploads a resolved image to tsuzura" do
      png = "\x89PNG\r\n\x1A\n".b
      @repo.write_asset!(@memo, filename: "photo.png", io: StringIO.new(png))
      captured = {}
      result = TsuzuraUpload::Result.new(
        tsuzura_media_id: "01JABCDEFGHJKMNPQRSTVWXYZ0",
        filename: "photo.png"
      )
      original = TsuzuraUpload.method(:call)
      TsuzuraUpload.define_singleton_method(:call) do |file:, cookie_header:|
        captured[:body] = file.read
        captured[:filename] = file.original_filename
        captured[:content_type] = file.content_type
        captured[:cookie_header] = cookie_header
        result
      end

      actual = MemoImages.upload(
        memo: @memo,
        relative_path: "photo.png",
        cookie_header: "session=abc",
        repo: @repo
      )

      assert_equal result, actual
      assert_equal png, captured[:body]
      assert_equal "photo.png", captured[:filename]
      assert_equal "image/png", captured[:content_type]
      assert_equal "session=abc", captured[:cookie_header]
    ensure
      TsuzuraUpload.define_singleton_method(:call, original)
    end
  end
end
