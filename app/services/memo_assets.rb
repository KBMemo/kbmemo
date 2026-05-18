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

  def self.delete!(memo, relative_path:, repo: MemoRepository.new)
    new(repo: repo).delete!(memo, relative_path: relative_path)
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
      url: asset_url_for(memo, filename)
    }
  end

  def resolve_path!(memo, filename)
    path = find_asset_file(memo, filename)
    raise InvalidFile, "画像が見つかりません" unless path&.file? && path.exist?
    raise InvalidFile, "画像が見つかりません" unless path_under_assets_dir?(memo, path)

    path
  end

  def delete!(memo, relative_path:)
    unless memo.image_assets_uploadable?
      raise InvalidFile, "メモを Git にコミットしてから削除してください"
    end

    path = resolve_path!(memo, relative_path)
    safe = path.relative_path_from(@repo.assets_dir_absolute_for(memo)).to_s
    path_rel = path.relative_path_from(@repo.root).to_s
    remove_companion_svg!(memo, safe)
    FileUtils.rm_f(path)
    @repo.remove_tracked_path!(path_rel)
  end

  def self.asset_url_for(memo, filename)
    relative = MemoAssetPath.normalize!(filename)
    Rails.application.routes.url_helpers.asset_memo_path(memo, relative)
  end

  private

  def asset_url_for(memo, filename)
    self.class.asset_url_for(memo, filename)
  end

  def remove_companion_svg!(memo, source_relative)
    ext = File.extname(source_relative).downcase
    return unless source_relative.start_with?("diagrams/") && MemoDiagram::ALLOWED_EXTENSIONS.include?(ext)

    macro = source_relative.sub(%r{\Adiagrams/}, "")
    svg_rel = MemoDiagram.svg_relative_path(macro)
    svg_path = @repo.absolute_asset_path_for(memo, svg_rel)
    return unless svg_path.file?

    svg_repo_rel = svg_path.relative_path_from(@repo.root).to_s
    FileUtils.rm_f(svg_path)
    @repo.remove_tracked_path!(svg_repo_rel)
  rescue MemoDiagram::InvalidPath
    nil
  end

  def find_asset_file(memo, filename)
    assets_dir = @repo.assets_dir_absolute_for(memo)

    if MemoAssetPath.safe_relative?(filename)
      exact = MemoAssetPath.existing_relative!(filename)
      path = assets_dir.join(exact)
      return path if path.file?
    end

    safe = MemoAssetPath.normalize!(filename)
    assets_dir.join(safe)
  rescue InvalidFile
    nil
  end

  def path_under_assets_dir?(memo, path)
    assets_root = @repo.assets_dir_absolute_for(memo).expand_path
    path.expand_path.to_s.start_with?("#{assets_root}/") || path.expand_path == assets_root
  end

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
