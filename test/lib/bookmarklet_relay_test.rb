# frozen_string_literal: true

require "test_helper"

class BookmarkletRelayTest < ActiveSupport::TestCase
  test "keeps the full-page success confirmation open until the user closes it" do
    source = Rails.root.join("public/bookmarklets/relay.html").read

    assert_includes source, "openLink.target = '_blank'"
    assert_includes source, "openLink.addEventListener('click'"
    assert_includes source, "window.setTimeout(requestClose, 0)"
    assert_includes source, "const CLIP_CLOSE = 'kbmemo-clip-close'"
    assert_includes source, "closeBtn.addEventListener('click', requestClose)"
    assert_not_includes source, "SUCCESS_CLOSE_DELAY_MS"
    assert_includes source, "function closeRelay()"
    assert_includes source, "window.close()"
  end

  test "closes selection clips after a successful save" do
    relay_source = Rails.root.join("public/bookmarklets/relay.html").read
    bookmarklet_source = Rails.root.join("public/bookmarklets/kbmemo_clip_api.js").read

    assert_includes relay_source, "if (event.data.mode === 'selection')"
    assert_includes relay_source, "requestClose()"
    assert_includes bookmarklet_source, "event.data.ok && clipPayload.mode === 'selection'"
    assert_includes bookmarklet_source, "popup.close()"
  end

  test "updates the relay title for success and failure" do
    source = Rails.root.join("public/bookmarklets/relay.html").read

    assert_includes source, "document.title = title"
    assert_includes source, "kbmemo に保存しました"
    assert_includes source, "kbmemo への保存に失敗しました"
  end

  test "new bookmarklets close the relay from the opener after an explicit close request" do
    source = Rails.root.join("public/bookmarklets/kbmemo_clip_api.js").read

    assert_includes source, "var CLIP_CLOSE = 'kbmemo-clip-close';"
    assert_includes source, "event.data.type === CLIP_CLOSE"
    assert_includes source, "popup.close()"
  end

  test "forwards clip mode and shows summary progress" do
    source = Rails.root.join("public/bookmarklets/relay.html").read

    assert_includes source, "mode: event.data.mode"
    assert_includes source, "サマリーを生成中"
  end

  test "does not treat a disconnected opener as a clip failure" do
    source = Rails.root.join("public/bookmarklets/relay.html").read

    assert_includes source, "function notifyOpener(message)"
    assert_includes source, "if (!window.opener || window.opener.closed) return"
    assert_includes source, "notifyOpener({ type: CLIP_DONE, ok: true"
    assert_not_includes source, "window.opener.postMessage(\n                { type: CLIP_DONE"
  end
end
