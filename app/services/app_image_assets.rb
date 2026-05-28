# frozen_string_literal: true

# AsciiDoc `image::/images/filename[]` 向けに Propshaft（app/assets/images 等）を解決する。
module AppImageAssets
  class Error < StandardError; end
  class Missing < Error; end

  module_function

  def find!(raw_path)
    logical = normalize_logical_path!(raw_path)
    asset = assembly.load_path.find(logical)
    raise Missing, "画像が見つかりません" unless asset

    asset
  end

  def public_path(raw_path)
    logical = normalize_logical_path!(raw_path)
    path = resolver.resolve(logical) || digested_public_path(logical)
    normalize_public_path(path)
  end

  def normalize_logical_path!(raw_path)
    path = raw_path.to_s.unicode_normalize(:nfc).strip.tr("\\", "/")
    path = path.delete_prefix("./")
    path = path.sub(%r{\A/images/}i, "")

    raise Missing, "パスが空です" if path.blank?
    raise Missing, "不正なパスです" if path.include?("..") || path.start_with?("/")

    path
  end

  def assembly
    Rails.application.assets
  end

  def resolver
    assembly.resolver
  end

  def digested_public_path(logical)
    asset = assembly.load_path.find(logical)
    return nil unless asset

    prefix = assembly.prefix.to_s.delete_suffix("/")
    normalize_public_path("#{prefix}/#{asset.digested_path}")
  end

  def normalize_public_path(path)
    return nil if path.blank?

    path.to_s.sub(%r{\A/+(?=/|\w)}, "/")
  end
  private_class_method :digested_public_path, :normalize_public_path
end
