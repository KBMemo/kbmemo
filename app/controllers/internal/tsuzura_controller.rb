# frozen_string_literal: true

module Internal
  class TsuzuraController < ApplicationController
    skip_before_action :require_authentication
    skip_before_action :set_nav_boards
    skip_before_action :set_nav_notebooks

    before_action :authenticate_internal_or_user!

    def authorize
      memo = Memo.find(params.require(:memo_id))
      authorize memo, :show?

      authorizer = Tsuzura::Authorizer.new(memo: memo)
      urls = authorizer.sign_media_urls(params[:media_ids])
      album_urls = sign_album_media_urls(params[:album_ids], authorizer)

      render json: { urls: urls.merge(album_urls) }
    end

    private

    def authenticate_internal_or_user!
      return if internal_secret_valid?
      return if rodauth.rails_account

      head :unauthorized
    end

    def internal_secret_valid?
      expected = ENV["KBMEMO_TSUZURA_INTERNAL_SECRET"].presence ||
        Rails.application.credentials.dig(:tsuzura, :internal_secret).presence
      provided = request.headers["X-Kbmemo-Internal-Secret"].to_s
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, provided)
    end

    def sign_album_media_urls(album_ids, authorizer)
      Array(album_ids).each_with_object({}) do |raw_id, urls|
        album = Tsuzura::Client.fetch_album(raw_id)
        next unless album

        Array(album["media_item_ids"]).each do |media_id|
          id = media_id.to_s.upcase
          urls[id] = authorizer.sign_media_url(id)
        end
      end
    end
  end
end
