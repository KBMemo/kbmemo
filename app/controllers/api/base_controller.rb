# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    include Pundit::Authorization
    include Rails.application.routes.url_helpers

    before_action :authenticate_clip_api_token!

    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

    private

    def authenticate_clip_api_token!
      @current_account = Account.find_by_clip_api_token(bearer_token)
      return if @current_account

      render json: { error: "認証に失敗しました。" }, status: :unauthorized
    end

    def bearer_token
      auth = request.authorization.to_s
      return auth.delete_prefix("Bearer ").strip if auth.start_with?("Bearer ")

      nil
    end

    def pundit_user
      @current_account
    end

    def user_not_authorized
      render json: { error: "権限がありません。" }, status: :forbidden
    end

    def default_url_options
      { host: request.host, port: request.optional_port, protocol: request.protocol.chomp("://") }
    end
  end
end
