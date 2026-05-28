# frozen_string_literal: true

require "set"
require "cgi"

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

  # image マクロ内の `/memos/:id/assets/...` を相対パスへ（imagesdir 二重付与の防止）
  def self.normalize_image_macro_paths(body)
    body.to_s.gsub(IMAGE_MACRO) do |match|
      block_path = Regexp.last_match(1)
      inline_path = Regexp.last_match(2)
      path = (block_path || inline_path).to_s.strip
      relative = normalize_asset_path(path)
      if match.start_with?("image::")
        match.sub(path, relative)
      else
        match.sub(path, relative)
      end
    end
  end

  def self.normalize_asset_path(path)
    path = path.to_s.unicode_normalize(:nfc).gsub("\\", "/")
    path = path.delete_prefix("./")
    path = strip_pseudo_image_uri_scheme(path)

    loop do
      if (match = path.match(%r{\A/memos/\d+/assets/(.+)\z}i))
        path = decode_asset_path_segments(match[1])
      elsif (match = path.match(%r{\Amemos/\d+/assets/(.+)\z}i))
        path = decode_asset_path_segments(match[1])
      else
        break
      end
    end

    path
  end

  KNOWN_URI_SCHEME = /\A(?:https?|data|file|ftp|mailto|javascript):/i
  IMAGE_FILE_EXT = /\.(png|jpe?g|gif|webp|svg|bmp|ico)\z/i

  def self.strip_pseudo_image_uri_scheme(path)
    path = path.to_s
    return path if path.match?(KNOWN_URI_SCHEME)

    if (match = path.match(/\A[a-z][a-z0-9+.-]*:(.+)\z/i))
      rest = match[1]
      return rest if rest.include?("/") || rest.match?(IMAGE_FILE_EXT)
    end

    path
  end

  def self.decode_asset_path_segments(path)
    path.split("/").map { |seg| CGI.unescape(seg) }.join("/")
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
    self.class.normalize_asset_path(path)
  end
end
