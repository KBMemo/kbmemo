/**
 * kbmemo Web クリップ API 直 POST ブックマークレット（読みやすいソース）
 *
 * 変更したら kbmemo_clip_api.bookmarklet.js も同期してください。
 * index.html で kbmemo URL と API トークンを埋め込んでからブックマークバーへドラッグします。
 *
 * 使い方:
 * 1. /bookmarklets/index.html を開く
 * 2. kbmemo URL とクリップ API トークンを入力
 * 3. 「kbmemo に保存」をブックマークバーへドラッグ
 * 4. Web ページでテキストを選択 → ブックマークレット実行
 */
void function kbmemoClipApiBookmarklet(baseUrl, apiToken) {
  function stripQuotes(value) {
    return (value || '').trim().replace(/^["']+|["']+$/g, '');
  }

  function resolveBaseOrigin(raw) {
    var value = stripQuotes(raw).replace(/\/$/, '');
    if (!value) return '';

    try {
      return new URL(value).origin;
    } catch (error) {
      return '';
    }
  }

  function clipApiUrl(baseOrigin) {
    return new URL('/api/clips', baseOrigin).href;
  }

  function absoluteKbmemoUrl(baseOrigin, path) {
    return new URL(path, baseOrigin).href;
  }

  var selection = window.getSelection();
  if (!selection || selection.isCollapsed) {
    window.alert('テキストを選択してから実行してください。');
    return;
  }

  var baseOrigin = resolveBaseOrigin(baseUrl);
  apiToken = stripQuotes(apiToken);

  if (!baseOrigin || !apiToken) {
    window.alert(
      'kbmemo の URL と API トークンが設定されていません。/bookmarklets/index.html から再インストールしてください。'
    );
    return;
  }

  if (!/^kbmemo_/.test(apiToken)) {
    window.alert(
      'API トークンが正しくありません。プロフィールで発行した kbmemo_... を /bookmarklets/index.html のトークン欄に入力して、ブックマークレットを作り直してください。'
    );
    return;
  }

  var range = selection.getRangeAt(0);
  var wrapper = document.createElement('div');
  wrapper.appendChild(range.cloneContents());

  var url = window.location.href;
  var title = document.title;
  var metadata = JSON.stringify({ url: url, title: title });
  var html =
    '<!--kbmemo:' + metadata + '-->' +
    '<blockquote cite="' + url.replace(/"/g, '&quot;') + '">' + wrapper.innerHTML + '</blockquote>';
  var plain = selection.toString();

  fetch(clipApiUrl(baseOrigin), {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + apiToken,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({ html: html, url: url, title: title, plain: plain }),
  })
    .then(function (response) {
      return response
        .json()
        .catch(function () {
          return {};
        })
        .then(function (data) {
          return { ok: response.ok, status: response.status, data: data };
        });
    })
    .then(function (result) {
      if (!result.ok) {
        var msg =
          (result.data &&
            (result.data.error || (result.data.errors && result.data.errors.join(', ')))) ||
          'HTTP ' + result.status;
        throw new Error(msg);
      }

      var openPath = result.data.show_path || result.data.edit_path;
      if (openPath && window.confirm('kbmemo に保存しました。メモを開きますか？')) {
        window.open(absoluteKbmemoUrl(baseOrigin, openPath), '_blank', 'noopener');
      } else {
        window.alert('kbmemo に保存しました。');
      }
    })
    .catch(function (error) {
      window.alert('保存に失敗しました: ' + (error && error.message ? error.message : error));
    });
}(__KBMEMO_BASE__, __KBMEMO_TOKEN__);
