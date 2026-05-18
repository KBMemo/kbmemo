# frozen_string_literal: true

# メモ本文用の画像を Git 作業ツリー（{slug}.assets/）へ保存する。
class MemoAssets
  class Error < StandardError; end
  class InvalidFile < Error; end

  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp image/svg+xml].freeze
  SVG_EXTENSION = ".svg"
  MAX_BYTES = 10 * 1024 * 1024

  def self.upload(memo, file:, repo: MemoRepository.new)
    new(repo: repo).upload(memo, file)
  end

  def self.resolve_path!(memo, filename, repo: MemoRepository.new)
    new(repo: repo).resolve_path!(memo, filename)
  end

  def initialize(repo: MemoRepository.new)
    @repo = repo
  end

  def upload(memo, file)
    raise InvalidFile, "ファイルがありません" if file.blank?
    unless memo.image_assets_uploadable?
      raise InvalidFile, "メモを Git にコミットしてから画像をアップロードしてください"
    end

    validate!(file)
    filename = unique_filename(memo, sanitize_filename(original_filename_for(file)))
    io = io_for(file)
    io = StringIO.new(MemoSvgSanitizer.sanitize!(io.read)) if svg_upload?(file, filename)
    @repo.write_asset!(memo, filename: filename, io: io)

    {
      filename: filename,
      asciidoc: "image::#{filename}[]",
      url: Rails.application.routes.url_helpers.asset_memo_path(memo, filename)
    }
  end

  def resolve_path!(memo, filename)
    safe = sanitize_filename(filename)
    path = @repo.absolute_asset_path_for(memo, safe)
    raise InvalidFile, "画像が見つかりません" unless path.file? && path.exist?

    path
  end

  private

  def validate!(file)
    io = io_for(file)
    size = file.respond_to?(:size) ? file.size : io.size
    raise InvalidFile, "10MB 以下の画像にしてください" if size.to_i > MAX_BYTES

    type = content_type_for(file)
    return if type.present? && ALLOWED_CONTENT_TYPES.include?(type)

    raise InvalidFile, "PNG / JPEG / GIF / WebP / SVG のみアップロードできます"
  end

  def svg_upload?(file, filename)
    type = content_type_for(file)
    type == "image/svg+xml" || filename.to_s.downcase.end_with?(SVG_EXTENSION)
  end

  def content_type_for(file)
    type = file.content_type.to_s.downcase.presence if file.respond_to?(:content_type)
    type.presence || Marcel::MimeType.for(name: original_filename_for(file)).to_s.downcase
  end

  def io_for(file)
    if file.respond_to?(:tempfile)
      file.tempfile
    elsif file.respond_to?(:read)
      file
    else
      raise InvalidFile, "ファイルがありません"
    end
  end

  def original_filename_for(file)
    file.respond_to?(:original_filename) ? file.original_filename : "image.png"
  end

  def sanitize_filename(name)
    MemoAssetFilename.sanitize(name)
  end

  def unique_filename(memo, name)
    dir = @repo.assets_dir_absolute_for(memo)
    dir.mkpath
    stem = File.basename(name, ".*")
    ext = File.extname(name)
    ext = ".png" if ext.blank?

    n = 0
    loop do
      candidate = n.zero? ? "#{stem}#{ext}" : "#{stem}-#{n}#{ext}"
      return candidate unless dir.join(candidate).exist?

      n += 1
    end
  end
end
