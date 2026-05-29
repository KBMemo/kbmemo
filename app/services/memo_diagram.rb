# frozen_string_literal: true

# diagram:: マクロと Git 上のダイアグラムソース（.mmd / .puml 等）の対応。
class MemoDiagram
  class Error < StandardError; end
  class InvalidPath < Error; end

  MERMAID_EXTENSIONS = %w[.mmd .mermaid].freeze
  PLANTUML_EXTENSIONS = %w[.puml .plantuml .uml].freeze
  ALLOWED_EXTENSIONS = (MERMAID_EXTENSIONS + PLANTUML_EXTENSIONS).freeze

  # 図としてレンダリングできるソースブロックの言語名（[source,<name>]）→ エンジン。
  ENGINE_BY_LANG = {
    "plantuml" => :plantuml,
    "puml" => :plantuml,
    "uml" => :plantuml,
    "mermaid" => :mermaid
  }.freeze
  ENGINE_NAMES = ENGINE_BY_LANG.keys.freeze

  # [source,<lang>] の言語名から正規化したエンジン記号を返す（対象外は nil）。
  def self.engine_from_lang(name)
    ENGINE_BY_LANG[name.to_s.strip.downcase]
  end

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

  # Kroki へ送る前に Markdown のコードフェンス等を除去する。
  def self.normalize_source(engine, source)
    text = Utf8Bytes.coerce(source)
    case engine
    when :mermaid then normalize_mermaid_source(text)
    when :plantuml then normalize_plantuml_source(text)
    else text.strip
    end
  end

  def self.normalize_mermaid_source(text)
    stripped = text.strip
    if (match = stripped.match(/\A```(?:mermaid)?\s*\r?\n([\s\S]*?)\r?\n```\s*\z/i))
      return match[1].strip
    end

    stripped.sub(/\A```(?:mermaid)?\s*\r?\n/i, "").sub(/\r?\n```\s*\z/, "").strip
  end
  private_class_method :normalize_mermaid_source

  def self.normalize_plantuml_source(text)
    stripped = text.strip
    if (match = stripped.match(/\A```(?:plantuml|puml)?\s*\r?\n([\s\S]*?)\r?\n```\s*\z/i))
      return match[1].strip
    end

    stripped.sub(/\A```(?:plantuml|puml)?\s*\r?\n/i, "").sub(/\r?\n```\s*\z/, "").strip
  end
  private_class_method :normalize_plantuml_source

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
