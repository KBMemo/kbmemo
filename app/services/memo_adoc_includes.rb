# frozen_string_literal: true

# docs_sync メモ本文の include:: をリポジトリ docs/ から展開する（表示専用）。
class MemoAdocIncludes
  INCLUDE_LINE = /\Ainclude::(.+?)\[[^\]]*\]\s*\z/
  MAX_DEPTH = 10

  def initialize(memo:, docs_root: Rails.root.join("docs"))
    @memo = memo
    @docs_root = Pathname.new(docs_root)
    @source_path = memo.properties.dig("docs_sync", "source_path").to_s
    @base_dir = @docs_root.join(File.dirname(@source_path))
  end

  def expand(text)
    return text if text.blank?
    return text if @source_path.blank?

    expand_text(text.to_s, depth: 0, stack: Set.new)
  end

  private

  def expand_text(text, depth:, stack:)
    return warning_line("include depth limit exceeded") if depth >= MAX_DEPTH

    out = +""
    in_fenced = false
    text.each_line do |line|
      if line.match?(/\A```/)
        in_fenced = !in_fenced
        out << line
      elsif in_fenced
        out << line
      elsif (match = line.match(INCLUDE_LINE))
        target = match[1].strip
        if remote_include?(target)
          out << warning_line("remote include not supported: #{target}")
        else
          out << read_include(target, depth: depth, stack: stack)
        end
      else
        out << line
      end
    end
    out
  end

  def read_include(target, depth:, stack:)
    path = resolve_path(target)
    return warning_line("include not found: #{target}") unless path&.file?

    canonical = path.realpath.to_s
    return warning_line("include cycle detected: #{target}") if stack.include?(canonical)

    content = path.read(encoding: "UTF-8")
    body = KbmemoDocs::AdocSource.embedded_body(content)
    expand_text(body, depth: depth + 1, stack: stack.merge([ canonical ]))
  end

  def resolve_path(target)
    return nil if target.blank?

    candidate = @base_dir.join(target).cleanpath
    return nil unless jailed?(candidate)

    candidate
  end

  def jailed?(path)
    docs = @docs_root.expand_path
    expanded = path.expand_path
    expanded.to_s == docs.to_s || expanded.to_s.start_with?("#{docs}/")
  end

  def remote_include?(target)
    target.match?(/\A[a-z][a-z0-9+.-]*:/i)
  end

  def warning_line(message)
    "WARNING: #{message}\n"
  end
end
