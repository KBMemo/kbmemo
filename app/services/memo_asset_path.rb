# frozen_string_literal: true

# {slug}.assets/ 配下の相対パス（フラット画像と diagrams/*.svg 等）。
module MemoAssetPath
  module_function

  def normalize!(raw)
    s = raw.to_s.unicode_normalize(:nfc).strip
    raise MemoAssets::InvalidFile, "パスが空です" if s.blank?
    raise MemoAssets::InvalidFile, "不正なパスです" if s.include?("..") || s.start_with?("/")

    parts = s.split("/").reject(&:empty?)
    case parts.length
    when 1
      MemoAssetFilename.sanitize(parts[0])
    when 2
      raise MemoAssets::InvalidFile, "不正なパスです" unless parts[0] == "diagrams"

      "diagrams/#{MemoAssetFilename.sanitize(parts[1])}"
    else
      raise MemoAssets::InvalidFile, "不正なパスです"
    end
  end

end
