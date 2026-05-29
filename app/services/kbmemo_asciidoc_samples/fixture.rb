# frozen_string_literal: true

module KbmemoAsciidocSamples
  # `test/fixtures/asciidoc/syntax-quick-reference.adoc` を
  # `// kbmemo:syntax-ref:<id>` マーカー単位のサンプル断片へ分割する。
  #
  # 断片の本文は marker 行と `// === カテゴリ ===` 見出し行を除いた逐語コピー。
  # `comments` の節のように本文中の `//` 行が記法サンプルそのものになる場合があるため、
  # 行頭 `//` を一律に除去しない（カテゴリ見出しのみ除外する）。
  class Fixture
    Entry = Data.define(:syntax_ref_id, :category, :body)

    MARKER   = %r{\A//\s*kbmemo:syntax-ref:(\S+)\s*\z}
    CATEGORY = %r{\A//\s*={2,}\s*(.+?)\s*={2,}\s*\z}

    DEFAULT_CATEGORY = "Document"

    def self.default_path
      Rails.root.join("test/fixtures/asciidoc/syntax-quick-reference.adoc")
    end

    def self.load(path = default_path)
      new(File.read(path, encoding: "UTF-8")).entries
    end

    def initialize(content)
      @content = content.to_s
    end

    def entries
      segments = []
      current = nil
      category = nil

      @content.each_line do |line|
        chomped = line.chomp

        if (m = chomped.match(CATEGORY))
          category = m[1]
          next
        end

        if (m = chomped.match(MARKER))
          current = { id: m[1], category: category, lines: [] }
          segments << current
          next
        end

        next if current.nil?

        current[:lines] << chomped
      end

      segments.map do |seg|
        Entry.new(
          syntax_ref_id: seg[:id],
          category: seg[:category] || DEFAULT_CATEGORY,
          body: trim(seg[:lines])
        )
      end
    end

    private

    def trim(lines)
      lines = lines.dup
      lines.shift while lines.first&.strip&.empty?
      lines.pop while lines.last&.strip&.empty?
      lines.join("\n")
    end
  end
end
