# frozen_string_literal: true

class MemoAssetsController < ApplicationController
  before_action :set_memo

  after_action :verify_authorized

  def create
    authorize @memo, :upload_asset?
    result = MemoAssets.upload(@memo, file: params.require(:file))
    render json: result
  rescue MemoAssets::InvalidFile => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    authorize @memo, :show_asset?
    path = MemoAssets.resolve_path!(@memo, asset_filename_from_params)
    apply_svg_asset_headers(path)
    send_file path, disposition: :inline, type: Marcel::MimeType.for(path)
  rescue MemoAssets::InvalidFile
    head :not_found
  end

  def destroy
    authorize @memo, :upload_asset?
    MemoAssets.delete!(@memo, relative_path: asset_filename_from_params)
    head :no_content
  rescue MemoAssets::InvalidFile => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_memo
    @memo = policy_scope(Memo).find(params[:id])
  end

  def asset_filename_from_params
    value = params[:asset_path].presence || params[:filename]
    value = value.join("/") if value.is_a?(Array)
    value = value.to_s
    return value if value.blank?

    # filename=icon.svg 等が format に分離された場合（.svg / .jpeg 等）
    if params[:format].present?
      fmt = params[:format].to_s.delete_prefix(".")
      value = "#{value}.#{fmt}" unless value.end_with?(".#{fmt}")
    end

    value
  end

  def apply_svg_asset_headers(path)
    return unless path.extname.downcase == MemoAssets::SVG_EXTENSION

    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] =
      "default-src 'none'; script-src 'none'; object-src 'none'; frame-src 'none'; style-src 'unsafe-inline'"
  end
end
