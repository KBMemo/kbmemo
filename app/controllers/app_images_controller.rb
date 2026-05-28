# frozen_string_literal: true

class AppImagesController < ApplicationController
  skip_before_action :require_authentication

  def show
    logical = filename_param
    asset = AppImageAssets.find!(logical)
    public_path = AppImageAssets.public_path(logical)

    if public_path.present?
      redirect_to public_path, allow_other_host: false
      return
    end

    send_file asset.path.to_s, disposition: :inline, type: asset.content_type.to_s
  rescue AppImageAssets::Missing
    head :not_found
  end

  private

  def filename_param
    value = params[:filename]
    value = value.join("/") if value.is_a?(Array)
    value.to_s
  end
end
