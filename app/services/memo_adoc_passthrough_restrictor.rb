# frozen_string_literal: true

# AsciiDoc passthrough（++++ / pass:[] / +++）を HTML 変換前に無害化する。
# DB 上のソースは変更せず、表示・プレビュー用パイプラインでのみ適用する。
class MemoAdocPassthroughRestrictor
  BLOCK_PASSTHROUGH_DELIM = "++++"

  # [stem] / [latexmath] / [asciimath] ブロックの ++++ は passthrough（生 HTML）ではなく
  # 数式ブロック（KaTeX 変換対象）なので neutralize しない。
  STEM_BLOCK_ATTR = /\A\[(?:stem|latexmath|asciimath)\b/

  class << self
    def restrict(text)
      new(text).restrict
    end
  end

  def initialize(text)
    @text = text.to_s
  end

  def restrict
    return @text if @text.blank?

    restrict_inline_passthrough(restrict_block_passthrough(@text))
  end

  private

  def restrict_block_passthrough(source)
    lines = source.split("\n", -1)
    index = 0

    while index < lines.length
      unless lines[index]&.strip == BLOCK_PASSTHROUGH_DELIM
        index += 1
        next
      end

      open_line = index
      close_line = open_line
      scan = open_line + 1

      while scan < lines.length
        if lines[scan]&.strip == BLOCK_PASSTHROUGH_DELIM
          close_line = scan
          break
        end
        scan += 1
      end

      if stem_block?(lines, open_line)
        index = close_line == open_line ? open_line + 1 : close_line + 1
        next
      end

      lines[open_line] = lines[open_line].sub(BLOCK_PASSTHROUGH_DELIM, "....")

      if close_line == open_line
        lines << "...."
        index = lines.length
        next
      end

      lines[close_line] = lines[close_line].sub(BLOCK_PASSTHROUGH_DELIM, "....")
      index = close_line + 1
    end

    lines.join("\n")
  end

  # 開始 ++++ の直上にある連続メタ行（属性 [..] / タイトル .xxx）に
  # stem/latexmath/asciimath 属性があれば数式ブロックとみなす。
  def stem_block?(lines, open_line)
    i = open_line - 1
    while i >= 0
      line = lines[i].to_s.strip
      break if line.empty?
      return true if line.match?(STEM_BLOCK_ATTR)
      break unless line.start_with?("[", ".")

      i -= 1
    end
    false
  end

  def restrict_inline_passthrough(source)
    source
      .gsub(/(?<!\\)pass:\[/, '\pass:[')
      .gsub(/(?<!\\)\+\+\+([^+\n]*)(?<!\\)\+\+\+/) { "\\+++#{::Regexp.last_match(1)}+++" }
  end
end
