# frozen_string_literal: true

# メモアセットのファイル名を Git・URL・AsciiDoc 向けに正規化する。
module MemoAssetFilename
  DEFAULT = "image.png"
  IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .svg].freeze
  MAX_LENGTH = 200
  # OS 禁止文字 + AsciiDoc 画像マクロを壊す [ ]
  FORBIDDEN = /[\x00-\x1f\x7f\/\\:\*\?\"<>\|\[\]]/

  module_function

  def sanitize(name)
    base = File.basename(name.to_s.unicode_normalize(:nfc))
    base = base.tr(" ", "_").gsub(FORBIDDEN, "_").gsub(/_+/, "_")

    ext = File.extname(base)
    stem = File.basename(base, ".*")
    stem = stem.gsub(/\A[.\s_]+|[.\s_]+\z/u, "")

    ext = ".png" if ext.blank? && !known_asset_name?(base)

    candidate =
      if stem.blank?
        default_name_for_extension(ext)
      else
        name = "#{stem}#{ext}"
        invalid_name?(name) ? DEFAULT : name
      end

    truncate_preserving_ext(candidate)
  end

  def invalid_name?(name)
    name.blank? || name == "." || name == ".." || name.include?("/")
  end

  def known_asset_name?(name)
    ext = File.extname(name.to_s).downcase
    ext.present? && (IMAGE_EXTENSIONS.include?(ext) || MemoDiagram::ALLOWED_EXTENSIONS.include?(ext))
  end
  private_class_method :known_asset_name?

  def default_name_for_extension(ext)
    case ext.to_s.downcase
    when ".svg" then "image.svg"
    else DEFAULT
    end
  end
  private_class_method :default_name_for_extension

  def truncate_preserving_ext(name)
    return name if name.length <= MAX_LENGTH

    ext = File.extname(name)
    stem = File.basename(name, ".*")
    max_stem = [ MAX_LENGTH - ext.length, 1 ].max
    "#{stem[0, max_stem]}#{ext}"
  end
end
