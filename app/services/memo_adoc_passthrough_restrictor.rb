# frozen_string_literal: true

# AsciiDoc passthrough（++++ / pass:[] / +++）を HTML 変換前に無害化する。
# DB 上のソースは変更せず、表示・プレビュー用パイプラインでのみ適用する。
class MemoAdocPassthroughRestrictor
  BLOCK_PASSTHROUGH_DELIM = "++++"

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

  def restrict_inline_passthrough(source)
    source
      .gsub(/(?<!\\)pass:\[/, '\pass:[')
      .gsub(/(?<!\\)\+\+\+([^+\n]*)(?<!\\)\+\+\+/) { "\\+++#{::Regexp.last_match(1)}+++" }
  end
end
