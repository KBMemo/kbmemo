# frozen_string_literal: true

require "set"

# 本文中で参照されている image:: / diagram:: パスを収集する。
class MemoBodyReferences
  IMAGE_MACRO = /image::([^\[\]\s]+)(?:\[[^\]]*\])?|image:([^\[\]\s]+)(?:\[[^\]]*\])?/
  # 非貪欲 +? だと diagram::flow.mmd[] のパスが1文字になるため、[] 手前まで貪欲に取る
  DIAGRAM_MACRO = /diagram::([^\[\]]+)(?:\[[^\]]*\])?/

  def initialize(body)
    @body = body.to_s
    @asset_paths = Set.new
    @diagram_keys = Set.new
    scan!
  end

  def asset_path?(relative_path)
    @asset_paths.include?(normalize_path(relative_path))
  end

  def diagram_key?(diagram_key)
    @diagram_keys.include?(diagram_key.to_s)
  end

  private

  def scan!
    in_fenced = false
    @body.each_line do |line|
      if line.match?(/^\s*```/)
        in_fenced = !in_fenced
        next
      end
      next if in_fenced

      line.scan(DIAGRAM_MACRO) do |path|
        key = MemoDiagram.normalize_macro_path(path.to_s)
        @diagram_keys.add(key) if key.present?
      end

      line.scan(IMAGE_MACRO) do |block_path, inline_path|
        path = (block_path || inline_path).to_s.strip
        add_path(path)
      end
    end
  end

  def add_path(path)
    return if path.blank?

    normalized = normalize_path(path)
    @asset_paths.add(normalized) if normalized.present?

    if normalized.start_with?("diagrams/") && normalized.end_with?(".svg")
      macro = normalized.sub(%r{\Adiagrams/}, "").sub(/\.svg\z/i, "")
      ext = File.extname(macro)
      @diagram_keys.add(macro) if ext.present?
    end
  end

  def normalize_path(path)
    path = path.unicode_normalize(:nfc).gsub("\\", "/")
    path.delete_prefix("./")
  end
end
