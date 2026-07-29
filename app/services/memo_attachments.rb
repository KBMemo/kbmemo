# frozen_string_literal: true

require "set"

# メモの Git アセット一覧（ダイアグラム + 画像 + 文書）と本文参照状態。
class MemoAttachments
  Entry = Data.define(
    :name,
    :relative_path,
    :kind,
    :referenced,
    :svg_missing,
    :edit_url,
    :insert_text,
    :delete_path
  )

  IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .svg].freeze

  def self.list(memo, body:, repo: MemoRepository.new)
    new(repo: repo).list(memo, body: body)
  end

  def initialize(repo: MemoRepository.new)
    @repo = repo
  end

  def list(memo, body:)
    return [] unless memo.persisted? && memo.image_assets_uploadable?

    refs = MemoBodyReferences.new(body)
    entries = []
    seen = Set.new

    MemoDiagrams.list(memo, repo: @repo).each do |diagram|
      rel = diagram[:source_relative]
      seen.add(rel)
      entries << diagram_entry(memo, diagram, refs)
    end

    assets_dir = @repo.assets_dir_absolute_for(memo)
    if assets_dir.directory?
      Dir.glob(assets_dir.join("**", "*"), File::FNM_DOTMATCH).sort.each do |abs|
        next unless File.file?(abs)

        rel = Pathname.new(abs).relative_path_from(assets_dir).to_s
        next if seen.include?(rel)
        next if skip_companion_svg?(rel, entries)
        next unless listable_asset?(rel)

        seen.add(rel)
        entries << asset_entry(memo, rel, refs)
      end
    end

    entries.sort_by { |e| [ e.kind == :diagram ? 0 : e.kind == :image ? 1 : 2, e.name.downcase ] }
  end

  private

  def diagram_entry(memo, diagram, refs)
    key = diagram[:diagram_key]
    source_relative = diagram[:source_relative]
    referenced = refs.diagram_key?(key) || refs.asset_path?(source_relative)
    Entry.new(
      name: key,
      relative_path: source_relative,
      kind: :diagram,
      referenced: referenced,
      svg_missing: !diagram[:svg_exists],
      edit_url: diagram[:edit_url],
      insert_text: diagram[:asciidoc],
      delete_path: referenced ? nil : source_relative
    )
  end

  def asset_entry(memo, relative_path, refs)
    referenced = refs.asset_path?(relative_path)
    image = MemoAssets.image?(relative_path)
    Entry.new(
      name: File.basename(relative_path),
      relative_path: relative_path,
      kind: image ? :image : :document,
      referenced: referenced,
      svg_missing: false,
      edit_url: nil,
      insert_text: image ? "image::#{relative_path}[]" : "attachment::#{relative_path}[]",
      delete_path: referenced ? nil : relative_path
    )
  end

  def skip_companion_svg?(relative_path, diagram_entries)
    return false unless relative_path.start_with?("diagrams/") && relative_path.downcase.end_with?(".svg")

    diagram_entries.any? do |entry|
      macro = entry.relative_path.delete_prefix("diagrams/")
      MemoDiagram.svg_relative_path(macro) == relative_path
    rescue MemoDiagram::InvalidPath
      false
    end
  end

  def listable_asset?(relative_path)
    ext = File.extname(relative_path).downcase
    return false if relative_path.start_with?("diagrams/") && MemoDiagram::ALLOWED_EXTENSIONS.include?(ext)

    IMAGE_EXTENSIONS.include?(ext) || MemoAssets.document?(relative_path)
  end
end
