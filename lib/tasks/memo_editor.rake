# frozen_string_literal: true

namespace :memo_editor do
  desc "Print Phase 5 editor smoke checklist (see docs/architecture/memo-body-editor-roadmap.adoc)"
  task smoke_checklist: :environment do
    puts <<~TEXT
      Phase 5 エディタ — スモークチェック（1 メモで通す）

      編集: /memos/:id/edit  表示: /memos/:id

      [ ] リスト（入れ子・番号付き）
      [ ] NOTE / WARNING 等 admonition
      [ ] [source,ruby] + ---- コードブロック
      [ ] |===| pipe 表
      [ ] image:: アセット画像（D&D / 貼付）
      [ ] diagram::*.mmd[]（Kroki 起動・SVG 再保存）
      [ ] stem:[...] / latexmath:[...] / [stem]++++ ブロック
      [ ] [[wiki-link]] 解決・クリック

      性能（任意）: 約 3000 行メモでスクロール・入力遅延を確認

      詳細: docs/architecture/memo-body-editor-roadmap.adoc
    TEXT
  end

  desc "Write a large AsciiDoc body to tmp/ for manual perf testing (default 3000 lines)"
  task perf_fixture: :environment do
    lines = (ENV["LINES"] || 3000).to_i
    path = Rails.root.join("tmp/memo_editor_perf_fixture.adoc")
    FileUtils.mkdir_p(path.dirname)

    body = +"= Perf fixture\n\n"
    lines.times do |i|
      body << "* item #{i}\n"
      # AsciiDoc はリスト直後の NOTE: を admonition にしない（空行でブロックを切る）
      if (i % 50).zero?
        body << "\nNOTE: block #{i}\nline two\n\n"
      end
    end

    path.write(body)
    puts "Wrote #{lines} lines to #{path}"
    puts "Paste into a memo body in the editor and check scroll/input latency."
  end
end
