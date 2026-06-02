# frozen_string_literal: true

module Internal
  class TsuzuraController < ApplicationController
    skip_before_action :require_authentication
    skip_before_action :set_nav_boards
    skip_before_action :set_nav_notebooks

    before_action :authenticate_internal_or_user!

    def albums
      return head :unauthorized unless rodauth.rails_account

      body = Tsuzura::Client.list_albums(owner_account_id: rodauth.rails_account.id)
      if body.nil?
        return render json: {
          albums: [],
          error: "Tsuzura API に接続できません。kbmemo-media が起動しているか TSUZURA_BASE_URL / KBMEMO_TSUZURA_INTERNAL_SECRET を確認してください。"
        }, status: :service_unavailable
      end

      render json: body
    end

    def album
      return head :unauthorized unless rodauth.rails_account

      data = Tsuzura::Client.fetch_album(params[:id])
      return head :not_found unless data
      return head :forbidden unless data["owner_account_id"] == rodauth.rails_account.id

      render json: data
    end

    def sign_urls
      memo = Memo.find(params.require(:memo_id))
      authorize memo, :show?

      authorizer = Tsuzura::Authorizer.new(memo: memo, viewer: rodauth.rails_account)
      urls = authorizer.sign_media_urls(params[:media_ids])
      albums = album_media_ids_map(params[:album_ids])
      album_urls = sign_album_media_urls(params[:album_ids], authorizer)

      render json: { urls: urls.merge(album_urls), albums: albums }
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

    def album_media_ids_map(album_ids)
      Array(album_ids).each_with_object({}) do |raw_id, albums|
        album = Tsuzura::Client.fetch_album(raw_id)
        next unless album

        id = raw_id.to_s.upcase
        media_ids = Array(album["media_item_ids"]).map { |media_id| media_id.to_s.upcase }.first(24)
        albums[id] = media_ids
      end
    end
  end
end
