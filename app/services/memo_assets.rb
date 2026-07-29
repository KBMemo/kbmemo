# frozen_string_literal: true

# メモ本文用の画像・文書を Git 作業ツリー（{slug}.assets/）へ保存する。
class MemoAssets
  class Error < StandardError; end
  class InvalidFile < Error; end

  IMAGE_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp image/svg+xml].freeze
  DOCUMENT_CONTENT_TYPES = {
    ".pdf" => %w[application/pdf],
    ".doc" => %w[application/msword],
    ".docx" => %w[application/vnd.openxmlformats-officedocument.wordprocessingml.document],
    ".xls" => %w[application/vnd.ms-excel],
    ".xlsx" => %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet],
    ".ppt" => %w[application/vnd.ms-powerpoint],
    ".pptx" => %w[application/vnd.openxmlformats-officedocument.presentationml.presentation],
    ".odt" => %w[application/vnd.oasis.opendocument.text],
    ".ods" => %w[application/vnd.oasis.opendocument.spreadsheet],
    ".odp" => %w[application/vnd.oasis.opendocument.presentation]
  }.freeze
  ALLOWED_CONTENT_TYPES = (IMAGE_CONTENT_TYPES + DOCUMENT_CONTENT_TYPES.values.flatten).freeze
  IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .svg].freeze
  DOCUMENT_EXTENSIONS = DOCUMENT_CONTENT_TYPES.keys.freeze
  SVG_EXTENSION = ".svg"
  PDF_EXTENSION = ".pdf"
  MAX_IMAGE_BYTES = 10 * 1024 * 1024
  MAX_DOCUMENT_BYTES = 25 * 1024 * 1024
  MAX_BYTES = MAX_IMAGE_BYTES # 既存の画像取り込みサービスとの互換用

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
      asciidoc: asciidoc_for(filename),
      url: asset_url_for(memo, filename)
    }
  end

  def resolve_path!(memo, filename)
    path = find_asset_file(memo, filename)
    raise InvalidFile, "添付ファイルが見つかりません" unless path&.file? && path.exist?
    raise InvalidFile, "添付ファイルが見つかりません" unless path_under_assets_dir?(memo, path)

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

  def self.image?(filename)
    IMAGE_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
  end

  def self.document?(filename)
    DOCUMENT_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
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
    filename = sanitize_filename(original_filename_for(file))
    kind = asset_kind(filename)
    raise InvalidFile, allowed_file_message unless kind

    max_bytes = kind == :image ? MAX_IMAGE_BYTES : MAX_DOCUMENT_BYTES
    raise InvalidFile, size_message_for(kind) if size.to_i > max_bytes

    type = declared_content_type_for(file)
    unless type.blank? || type == "application/octet-stream" || allowed_content_type?(filename, type)
      raise InvalidFile, allowed_file_message
    end

    validate_pdf_signature!(io, filename) if filename.downcase.end_with?(PDF_EXTENSION)
  ensure
    io.rewind if io&.respond_to?(:rewind)
  end

  def asset_kind(filename)
    return :image if self.class.image?(filename)
    return :document if self.class.document?(filename)

    nil
  end

  def allowed_content_type?(filename, type)
    if self.class.image?(filename)
      IMAGE_CONTENT_TYPES.include?(type)
    else
      DOCUMENT_CONTENT_TYPES.fetch(File.extname(filename).downcase, []).include?(type)
    end
  end

  def allowed_file_message
    "PNG / JPEG / GIF / WebP / SVG / PDF / Office 文書のみアップロードできます"
  end

  def size_message_for(kind)
    kind == :image ? "10MB 以下の画像にしてください" : "25MB 以下の文書にしてください"
  end

  def validate_pdf_signature!(io, filename)
    header = io.read(5)
    return if header == "%PDF-"

    raise InvalidFile, "PDF ファイルとして認識できません"
  end

  def svg_upload?(file, filename)
    type = declared_content_type_for(file)
    type == "image/svg+xml" || filename.to_s.downcase.end_with?(SVG_EXTENSION)
  end

  def declared_content_type_for(file)
    file.content_type.to_s.downcase.presence if file.respond_to?(:content_type)
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
    file.respond_to?(:original_filename) ? file.original_filename : "attachment"
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

  def asciidoc_for(filename)
    if self.class.image?(filename)
      "image::#{filename}[]"
    else
      "attachment::#{filename}[]"
    end
  end
end
