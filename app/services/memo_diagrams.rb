# frozen_string_literal: true

# ダイアグラムソースの作成・保存・Kroki レンダリング。
class MemoDiagrams
  class Error < StandardError; end

  def self.create!(memo, name:, engine:, repo: MemoRepository.new)
    new(repo: repo).create!(memo, name: name, engine: engine)
  end

  def self.save_and_render!(memo, source_relative:, source:, repo: MemoRepository.new)
    new(repo: repo).save_and_render!(memo, source_relative: source_relative, source: source)
  end

  def self.preview_render(source_relative:, source:)
    new.preview_render(source_relative: source_relative, source: source)
  end

  def self.list(memo, repo: MemoRepository.new)
    new(repo: repo).list(memo)
  end

  def initialize(repo: MemoRepository.new)
    @repo = repo
  end

  def create!(memo, name:, engine:)
    raise Error, "メモを Git にコミットしてからダイアグラムを作成してください" unless memo.image_assets_uploadable?

    engine = engine.to_sym
    ext = extension_for_engine(engine)
    base = MemoDiagram.normalize_macro_path(name)
    raise Error, "名前を入力してください" if base.blank?

    source_rel = "diagrams/#{base}#{ext}"
    raise Error, "既に存在します" if @repo.absolute_asset_path_for(memo, source_rel).exist?

    template = MemoDiagram.empty_template(engine)
    save_and_render!(memo, source_relative: source_rel, source: template)

    {
      source_relative: source_rel,
      asciidoc: MemoDiagram.asciidoc_for(source_rel),
      edit_url: edit_url_for(memo, source_rel)
    }
  end

  def save_and_render!(memo, source_relative:, source:)
    raise Error, "メモを Git にコミットしてから保存してください" unless memo.image_assets_uploadable?

    source_rel = source_relative.to_s
    engine = MemoDiagram.engine_for_filename(source_rel)
    svg_rel = svg_relative_for(source_rel)
    normalized = MemoDiagram.normalize_source(engine, source)

    @repo.write_asset!(memo, filename: source_rel, io: StringIO.new(normalized))
    svg_body = MemoDiagramRenderer.render(engine: engine, source: normalized)
    @repo.write_asset!(memo, filename: svg_rel, io: StringIO.new(svg_body))

    {
      source_relative: source_rel,
      svg_relative: svg_rel,
      asciidoc: MemoDiagram.asciidoc_for(source_rel)
    }
  end

  # Kroki で SVG を生成する（Git へは書き込まない）
  def preview_render(source_relative:, source:)
    source_rel = source_relative.to_s
    engine = MemoDiagram.engine_for_filename(source_rel)
    normalized = MemoDiagram.normalize_source(engine, source)
    MemoDiagramRenderer.render(engine: engine, source: normalized)
  end

  def read_source(memo, source_relative:)
    path = @repo.absolute_asset_path_for(memo, source_relative)
    raise Error, "ダイアグラムが見つかりません" unless path.file?

    path.read(encoding: "UTF-8")
  end

  # Git 作業ツリー上の diagrams/*.mmd|*.puml 一覧（編集ページへの導線用）
  def list(memo)
    dir = @repo.assets_dir_absolute_for(memo).join("diagrams")
    return [] unless dir.directory?

    dir.each_child.filter_map do |path|
      next unless path.file?

      name = path.basename.to_s
      ext = File.extname(name).downcase
      next unless MemoDiagram::ALLOWED_EXTENSIONS.include?(ext)

      source_rel = "diagrams/#{name}"
      {
        diagram_key: name,
        source_relative: source_rel,
        engine: MemoDiagram.engine_for_filename(source_rel),
        asciidoc: MemoDiagram.asciidoc_for(source_rel),
        edit_url: edit_url_for(memo, source_rel),
        svg_exists: @repo.absolute_asset_path_for(memo, svg_relative_for(source_rel)).file?
      }
    end.sort_by { |e| e[:diagram_key] }
  end

  private

  def extension_for_engine(engine)
    case engine
    when :mermaid then ".mmd"
    when :plantuml then ".puml"
    else
      raise Error, "engine は mermaid または plantuml を指定してください"
    end
  end

  def svg_relative_for(source_rel)
    ext = File.extname(source_rel)
    source_rel.sub(/#{Regexp.escape(ext)}\z/i, ".svg")
  end

  def edit_url_for(memo, source_rel)
    key = source_rel.sub(%r{\Adiagrams/}, "")
    Rails.application.routes.url_helpers.edit_memo_diagram_path(memo, key)
  end
end
