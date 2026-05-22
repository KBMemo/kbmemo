/**
 * kbmemo Web クリップ用ブックマークレット（読みやすいソース）
 *
 * 変更したら kbmemo_clip.bookmarklet.js も同期してください。
 *
 * 使い方:
 * 1. /bookmarklets/index.html を開く
 * 2. 「kbmemo にコピー」リンクをブックマークバーへドラッグ
 * 3. Web ページでテキストを選択 → ブックマークレット実行
 * 4. kbmemo エディタで Ctrl+V
 */
void function kbmemoClipBookmarklet() {
  var selection = window.getSelection();
  if (!selection || selection.isCollapsed) {
    window.alert('テキストを選択してから実行してください。');
    return;
  }

  if (!window.isSecureContext || !navigator.clipboard || typeof ClipboardItem === 'undefined') {
    window.alert('HTTPS ページで、Clipboard API に対応した Chrome 等をご利用ください。');
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

  navigator.clipboard
    .write([
      new ClipboardItem({
        'text/html': new Blob([html], { type: 'text/html' }),
        'text/plain': new Blob([plain], { type: 'text/plain' }),
      }),
    ])
    .then(function () {
      window.alert('kbmemo 用にコピーしました。エディタで Ctrl+V してください。');
    })
    .catch(function (error) {
      window.alert('コピーに失敗しました: ' + error);
    });
}();
