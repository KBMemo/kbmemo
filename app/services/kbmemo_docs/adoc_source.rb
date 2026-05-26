# frozen_string_literal: true

module KbmemoDocs
  # リポジトリ docs/ 配下の .adoc 1 ファイルをパースする。
  class AdocSource
    FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n+/m
    DOCUMENT_TITLE = /\A=\s+[^\n]+\n+/

    attr_reader :source_path, :relative_path, :body, :front_matter

    def self.load(relative_path, root:)
      abs = Pathname.new(root).join(relative_path)
      raise Errno::ENOENT, relative_path unless abs.file?

      new(relative_path: relative_path.to_s, content: abs.read(encoding: "UTF-8"))
    end

    def initialize(relative_path:, content:)
      @relative_path = relative_path
      @source_path = relative_path
      parse(content)
    end

    def title
      from_meta = front_matter["title"].to_s.strip
      return from_meta if from_meta.present?

      Memo.derived_title_from_body(raw_body)
    end

    def slug_stem
      dir = Pathname.new(relative_path).dirname
      basename = File.basename(relative_path, ".adoc")
      raw = if dir.to_s == "." || dir.to_s.blank?
        basename
      else
        "#{dir}/#{basename}"
      end
      Memo.normalize_slug_fragment(raw.tr("/", "-")) || "doc"
    end

    def content_sha256
      @content_sha256 ||= Digest::SHA256.hexdigest(normalized_body)
    end

    def path_tags
      parts = Pathname.new(relative_path).dirname.to_s.split("/").reject { |p| p.blank? || p == "." }
      parts.map { |part| Memo.normalize_slug_fragment(part) }.compact
    end

    def memo_directory_segments
      [ "dev-docs", *Pathname.new(relative_path).dirname.to_s.split("/").reject { |p| p.blank? || p == "." } ]
    end

    private

    attr_reader :raw_body

    def parse(content)
      unparsed = if (match = content.match(FRONT_MATTER))
        @front_matter = YAML.safe_load(match[1]) || {}
        content.sub(FRONT_MATTER, "")
      else
        @front_matter = {}
        content
      end
      unparsed = unparsed.sub(/\A[\r\n]+/, "")
      @raw_body = unparsed
      @body = strip_document_title(unparsed)
    end

    def strip_document_title(text)
      return text if front_matter["title"].present?
      return text unless text.match?(DOCUMENT_TITLE)

      text.sub(DOCUMENT_TITLE, "").sub(/\A[\r\n]+/, "")
    end

    def normalized_body
      body.to_s.gsub(/\r\n?/, "\n")
    end
  end
end
