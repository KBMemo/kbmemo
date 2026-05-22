# frozen_string_literal: true

require "net/http"
require "uri"

# クリップ HTML 内の外部画像をメモアセットへ取り込み、src をローカル URL に差し替える。
class ClipImageImporter
  class Error < StandardError; end

  MAX_BYTES = MemoAssets::MAX_BYTES
  ALLOWED_CONTENT_TYPES = MemoAssets::ALLOWED_CONTENT_TYPES
  USER_AGENT = "kbmemo-clip/1.0"

  def initialize(memo, base_url: nil, repo: MemoRepository.new)
    @memo = memo
    @base_url = base_url.to_s.strip.presence
    @repo = repo
  end

  def localize!(html, src_format: :asset_url)
    fragment = Nokogiri::HTML.fragment(html.to_s)
    fragment.css("img[src]").each do |img|
      src = img["src"].to_s.strip
      next if skip_src?(src)

      absolute = resolve_absolute_url(src)
      next if absolute.blank?

      filename = import_remote!(absolute)
      next if filename.blank?

      img["src"] = image_src_for(filename, src_format)
    end

    fragment.to_html
  end

  private

  def image_src_for(filename, src_format)
    case src_format
    when :filename
      filename
    else
      MemoAssets.asset_url_for(@memo, filename)
    end
  end

  def skip_src?(src)
    return true if src.blank?
    return true if src.start_with?("data:", "blob:")
    return true if src.match?(%r{\A/memos/\d+/assets/}i)

    false
  end

  def resolve_absolute_url(src)
    base = @base_url.presence || "about:blank"
    URI.join(base, src).to_s
  rescue URI::InvalidURIError
    nil
  end

  def import_remote!(url)
    body, content_type, filename_hint = fetch(url)
    return nil if body.nil? || body.empty?

    raise Error, "10MB 以下の画像にしてください" if body.bytesize > MAX_BYTES

    type = normalized_content_type(content_type, body, filename_hint)
    raise Error, "PNG / JPEG / GIF / WebP / SVG のみ取り込めます" unless ALLOWED_CONTENT_TYPES.include?(type)

    filename = unique_filename(filename_hint, type)
    io = StringIO.new(body)
    io = StringIO.new(MemoSvgSanitizer.sanitize!(io.read)) if type == "image/svg+xml"
    @repo.write_asset!(@memo, filename: filename, io: io)
    filename
  rescue Error
    nil
  end

  def fetch(url, redirect_limit: 3)
    uri = URI.parse(url)
    raise Error, "HTTP/HTTPS のみ取り込めます" unless uri.is_a?(URI::HTTP)

    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.is_a?(URI::HTTPS),
      open_timeout: 5,
      read_timeout: 15
    ) do |http|
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Referer"] = @base_url if @base_url.present?

      response = http.request(request)
      if response.is_a?(Net::HTTPRedirection) && redirect_limit.positive?
        location = response["location"]
        return fetch(location, redirect_limit: redirect_limit - 1) if location.present?
      end

      raise Error, "画像の取得に失敗しました" unless response.is_a?(Net::HTTPSuccess)

      filename_hint = filename_from_url(uri.path)
      [ response.body, response.content_type.to_s, filename_hint ]
    end
  rescue Error
    raise
  rescue StandardError
    raise Error, "画像の取得に失敗しました"
  end

  def normalized_content_type(header, body, filename_hint)
    type = header.to_s.split(";").first.to_s.strip.downcase.presence
    type = Marcel::MimeType.for(body, name: filename_hint).to_s.downcase if type.blank?
    type
  end

  def filename_from_url(path)
    MemoAssetFilename.sanitize(File.basename(path.to_s))
  end

  def unique_filename(name, content_type)
    sanitized = MemoAssetFilename.sanitize(name)
    ext = File.extname(sanitized)
    stem = File.basename(sanitized, ".*")
    ext = extension_for_content_type(content_type) if ext.blank?

    dir = @repo.assets_dir_absolute_for(@memo)
    dir.mkpath

    n = 0
    loop do
      candidate = n.zero? ? "#{stem}#{ext}" : "#{stem}-#{n}#{ext}"
      candidate = MemoAssetFilename.sanitize(candidate)
      return candidate unless dir.join(candidate).exist?

      n += 1
    end
  end

  def extension_for_content_type(content_type)
    case content_type
    when "image/jpeg" then ".jpg"
    when "image/png" then ".png"
    when "image/gif" then ".gif"
    when "image/webp" then ".webp"
    when "image/svg+xml" then ".svg"
    else ".png"
    end
  end
end
