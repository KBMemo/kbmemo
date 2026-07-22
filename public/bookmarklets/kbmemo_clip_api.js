/**
 * kbmemo Web クリップ API 保存ブックマークレット（読みやすいソース）
 *
 * 厳しい CSP（GitHub 等）ではページ上の fetch が禁止されるため、kbmemo の relay ページを
 * ポップアップで開き、そこから同一オリジンで /api/clips へ POST する。
 *
 * 変更したら kbmemo_clip_api.bookmarklet.js も同期してください。
 */
void function kbmemoClipApiBookmarklet(baseUrl, apiToken) {
  var RELAY_READY = 'kbmemo-clip-relay-ready';
  var CLIP = 'kbmemo-clip';
  var CLIP_DONE = 'kbmemo-clip-done';

  function stripQuotes(value) {
    return (value || '').trim().replace(/^["']+|["']+$/g, '')
  }

  function resolveBaseOrigin(raw) {
    var value = stripQuotes(raw).replace(/\/$/, '')
    if (!value) return ''

    try {
      return new URL(value).origin
    } catch (error) {
      return ''
    }
  }

  function relayPageUrl(baseOrigin) {
    return new URL('/bookmarklets/relay.html', baseOrigin).href
  }

  var selection = window.getSelection()
  if (!selection || selection.isCollapsed) {
    window.alert('テキストを選択してから実行してください。')
    return
  }

  var baseOrigin = resolveBaseOrigin(baseUrl)
  apiToken = stripQuotes(apiToken)

  if (!baseOrigin || !apiToken) {
    window.alert(
      'kbmemo の URL と Web クリップトークンが設定されていません。プロフィールからブックマークレットを取り直してください。'
    )
    return
  }

  if (!/^kbmemo_clip_/.test(apiToken)) {
    window.alert(
      'Web クリップトークンが正しくありません。プロフィールでトークンを再発行してブックマークレットを取り直してください。'
    )
    return
  }

  var range = selection.getRangeAt(0)
  var wrapper = document.createElement('div')
  wrapper.appendChild(range.cloneContents())

  var pageUrl = window.location.href
  var pageTitle = document.title
  var metadata = JSON.stringify({ url: pageUrl, title: pageTitle })
  var html =
    '<!--kbmemo:' +
    metadata +
    '-->' +
    '<blockquote cite="' +
    pageUrl.replace(/"/g, '&quot;') +
    '">' +
    wrapper.innerHTML +
    '</blockquote>'
  var plain = selection.toString()

  var clipPayload = {
    type: CLIP,
    token: apiToken,
    html: html,
    url: pageUrl,
    title: pageTitle,
    plain: plain,
  }

  var popup = window.open(
    relayPageUrl(baseOrigin),
    'kbmemo_clip_relay',
    'width=480,height=280'
  )

  if (!popup) {
    window.alert(
      'ポップアップがブロックされました。kbmemo への保存にはポップアップを許可するか、「kbmemo にコピー」ブックマークレットをお使いください。'
    )
    return
  }

  var finished = false
  var timeout = window.setTimeout(function () {
    if (finished) return
    finished = true
    window.removeEventListener('message', onMessage)
    window.alert('kbmemo への接続がタイムアウトしました。')
    try {
      popup.close()
    } catch (error) {
      /* ignore */
    }
  }, 60000)

  function onMessage(event) {
    if (finished) return
    if (event.source !== popup) return

    var originOk = false
    try {
      originOk = new URL(event.origin).origin === baseOrigin
    } catch (error) {
      originOk = false
    }
    if (!originOk) return

    if (event.data && event.data.type === RELAY_READY) {
      popup.postMessage(clipPayload, baseOrigin)
      return
    }

    if (!event.data || event.data.type !== CLIP_DONE) return

    finished = true
    window.clearTimeout(timeout)
    window.removeEventListener('message', onMessage)

    // Success and error feedback are shown in the relay popup (active window).
    // Avoid alert/confirm here: Chrome suppresses them on background tabs.
  }

  window.addEventListener('message', onMessage)
}(__KBMEMO_BASE__, __KBMEMO_TOKEN__)
