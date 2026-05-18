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

  # 一覧・削除 API 向け: サニタイズせず、実ファイルの相対パスを検証する
  def existing_relative!(raw)
    rel = raw.to_s.unicode_normalize(:nfc).strip
    raise MemoAssets::InvalidFile, "パスが空です" if rel.blank?
    raise MemoAssets::InvalidFile, "不正なパスです" unless safe_relative?(rel)

    parts = rel.split("/").reject(&:empty?)
    case parts.length
    when 1
      parts[0]
    when 2
      raise MemoAssets::InvalidFile, "不正なパスです" unless parts[0] == "diagrams"

      "diagrams/#{parts[1]}"
    else
      raise MemoAssets::InvalidFile, "不正なパスです"
    end
  end

  def safe_relative?(raw)
    rel = raw.to_s
    return false if rel.blank? || rel.include?("..") || rel.start_with?("/")

    parts = rel.split("/").reject(&:empty?)
    return false if parts.empty? || parts.length > 2
    return false if parts.length == 2 && parts[0] != "diagrams"

    parts.all? { |part| safe_segment?(part) }
  end

  def safe_segment?(part)
    part.present? &&
      part == File.basename(part) &&
      !part.include?("..") &&
      !part.match?(%r{[/\\]}) &&
      !part.match?(/[\x00-\x1f\x7f]/)
  end
  private_class_method :safe_segment?
end
