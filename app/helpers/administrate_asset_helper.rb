# frozen_string_literal: true

# Administrate のレイアウト用。stylesheet_link_tag は manifest があると Static リゾルバ経由になり、
# マニフェストに無い administrate のアセットで「load path にあるのに Not found」になる。
# load_path 上の Propshaft::Asset から digested URL を組み立て、Propshaft::Server が配信するパスに合わせる。
module AdministrateAssetHelper
  def administrate_asset_href(logical_path)
    asset = Rails.application.assets.load_path.find(logical_path)
    return if asset.nil?

    prefix = Rails.application.config.assets.prefix
    prefix = prefix.start_with?("/") ? prefix : "/#{prefix}"
    root = request&.script_name.to_s.chomp("/")
    "#{root}#{prefix}/#{asset.digested_path}"
  end
end
