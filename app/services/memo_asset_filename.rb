# frozen_string_literal: true

# メモアセットのファイル名を Git・URL・AsciiDoc 向けに正規化する。
module MemoAssetFilename
  DEFAULT = "image.png"
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

    ext = ".png" if ext.blank?
    candidate = "#{stem}#{ext}"
    candidate = DEFAULT if stem.blank? || invalid_name?(candidate)

    truncate_preserving_ext(candidate)
  end

  def invalid_name?(name)
    name.blank? || name == "." || name == ".." || name.include?("/")
  end

  def truncate_preserving_ext(name)
    return name if name.length <= MAX_LENGTH

    ext = File.extname(name)
    stem = File.basename(name, ".*")
    max_stem = [ MAX_LENGTH - ext.length, 1 ].max
    "#{stem[0, max_stem]}#{ext}"
  end
end
