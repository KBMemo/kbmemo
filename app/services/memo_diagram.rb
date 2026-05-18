# frozen_string_literal: true

# diagram:: マクロと Git 上のダイアグラムソース（.mmd / .puml 等）の対応。
class MemoDiagram
  class Error < StandardError; end
  class InvalidPath < Error; end

  MERMAID_EXTENSIONS = %w[.mmd .mermaid].freeze
  PLANTUML_EXTENSIONS = %w[.puml .plantuml .uml].freeze
  ALLOWED_EXTENSIONS = (MERMAID_EXTENSIONS + PLANTUML_EXTENSIONS).freeze

  DIAGRAM_MACRO = /diagram::([^\[\]]+?)(\[[^\]]*\])?/

  def self.engine_for_filename(filename)
    ext = File.extname(filename.to_s).downcase
    return :mermaid if MERMAID_EXTENSIONS.include?(ext)
    return :plantuml if PLANTUML_EXTENSIONS.include?(ext)

    raise InvalidPath, "対応していない拡張子です（Mermaid: .mmd / PlantUML: .puml）"
  end

  def self.kroki_type(engine)
    case engine
    when :mermaid then "mermaid"
    when :plantuml then "plantuml"
    else
      raise InvalidPath, "不明なダイアグラム種別です"
    end
  end

  # diagram::flow.mmd[] → diagrams/flow.mmd（assets 根からの相対パス）
  def self.source_relative_path(macro_path)
    name = normalize_macro_path(macro_path)
    raise InvalidPath, "ダイアグラムパスが空です" if name.blank?

    name = "diagrams/#{name}" unless name.start_with?("diagrams/")
    name
  end

  def self.svg_relative_path(macro_path)
    source = source_relative_path(macro_path)
    ext = File.extname(source)
    raise InvalidPath, "拡張子がありません" if ext.blank?

    source.sub(/#{Regexp.escape(ext)}\z/i, ".svg")
  end

  def self.normalize_macro_path(path)
    base = File.basename(path.to_s.unicode_normalize(:nfc))
    base = base.gsub(/[^\w.\-\p{L}\p{N}]/u, "_")
    base.gsub(/_+/, "_").gsub(/\A[._]+|[._]+\z/u, "")
  end

  def self.asciidoc_for(source_relative_path)
    "diagram::#{source_relative_path.sub(%r{\Adiagrams/}, '')}[]"
  end

  def self.empty_template(engine)
    case engine
    when :mermaid
      <<~SRC.rstrip
        graph TD
          A[Start] --> B[End]
      SRC
    when :plantuml
      <<~SRC.rstrip
        @startuml
        Alice -> Bob: hello
        @enduml
      SRC
    else
      ""
    end
  end
end
