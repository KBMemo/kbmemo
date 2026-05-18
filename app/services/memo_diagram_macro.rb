# frozen_string_literal: true

# diagram::path.mmd[] をキャッシュ済み SVG への image:: に展開（表示・プレビュー用）。
class MemoDiagramMacro
  BLOCK_LINE = /\Adiagram::([^\[\]]+?)(\[[^\]]*\])?\s*\z/

  def initialize(memo:, repo: MemoRepository.new)
    @memo = memo
    @repo = repo
  end

  def substitute(text)
    return text if text.blank? || !@memo&.persisted?

    out = +""
    in_fenced = false
    text.each_line do |line|
      if line.match?(/\A```/)
        in_fenced = !in_fenced
        out << line
      elsif in_fenced
        out << line
      else
        out << substitute_diagram_on_line(line)
      end
    end
    out
  end

  private

  def substitute_diagram_on_line(line)
    nl = line.end_with?("\n") ? "\n" : ""
    body = line.chomp

    if (m = body.match(BLOCK_LINE))
      return "#{replace_diagram(m[1])}#{nl}"
    end

    body.gsub(MemoDiagram::DIAGRAM_MACRO) do
      replace_diagram(Regexp.last_match(1).to_s)
    end + nl
  end

  def replace_diagram(macro_path)
    source_rel = MemoDiagram.source_relative_path(macro_path)
    svg_rel = MemoDiagram.svg_relative_path(macro_path)
    svg_abs = @repo.absolute_asset_path_for(@memo, svg_rel)

    if svg_abs.file?
      # Mermaid ラベルは foreignObject 内 HTML。img では描画されないため object で表示する。
      "image::#{svg_rel}[opts=interactive]"
    else
      missing_diagram_markup(source_rel)
    end
  rescue MemoDiagram::InvalidPath
    missing_diagram_markup(macro_path.to_s)
  end

  def missing_diagram_markup(label)
    "[.memo-diagram-missing]##{escape(label)}#"
  end

  def escape(text)
    text.to_s.gsub("#", '\\#')
  end
end
