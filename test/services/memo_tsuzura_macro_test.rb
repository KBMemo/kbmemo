# frozen_string_literal: true

require "test_helper"

class MemoTsuzuraMacroTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @account = accounts(:one)
    @ulid = ULID.generate.to_s
  end

  test "substitutes image media macro with signed url when viewer may show memo" do
    url = Tsuzura::MediaUrlSigner.sign(media_id: @ulid, memo_id: @memo.id)
    Tsuzura::MediaUrlSigner.stub(:sign, ->(**) { url }) do
      out = MemoTsuzuraMacro.new(memo: @memo, viewer: @account).substitute("image::media:#{@ulid}[width=720]\n")
      assert_includes out, url
      assert_includes out, "width=720"
    end
  end

  test "leaves media macro unchanged when viewer cannot show memo" do
    other = memos(:two)
    body = "image::media:#{@ulid}[]\n"
    out = MemoTsuzuraMacro.new(memo: other, viewer: @account).substitute(body)
    assert_equal body, out
  end

  test "expands album macro via tsuzura client" do
    album_id = ULID.generate.to_s
    media_id = ULID.generate.to_s
    Tsuzura::Client.stub(:fetch_album, { "media_item_ids" => [ media_id ] }) do
      signed = Tsuzura::MediaUrlSigner.sign(media_id: media_id, memo_id: @memo.id)
      Tsuzura::MediaUrlSigner.stub(:sign, ->(**) { signed }) do
        out = MemoTsuzuraMacro.new(memo: @memo, viewer: @account).substitute("album::#{album_id}[]\n")
        assert_includes out, signed
      end
    end
  end
end
