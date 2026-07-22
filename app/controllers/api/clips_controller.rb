# frozen_string_literal: true

module Api
  class ClipsController < BaseController
    skip_before_action :authenticate_api_token!
    before_action :authenticate_clip_token!, except: :options

    def create
      unless clip_payload_present?
        render json: { errors: [ "html または plain が必要です。" ] }, status: :unprocessable_entity
        return
      end

      authorize Memo.new(account: @current_account), :create?

      memo = ClipCreator.new(
        account: @current_account,
        html: clip_params[:html],
        url: clip_params[:url],
        title: clip_params[:title],
        plain: clip_params[:plain]
      ).call

      render json: {
        id: memo.id,
        edit_path: edit_memo_path(memo),
        show_path: memo_path(memo),
        slug: memo.slug,
        directory: memo.memo_directory.full_path
      }, status: :created
    rescue ClipCreator::Error => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
    end

    def options
      head :no_content
    end

    private

    def authenticate_clip_token!
      token = bearer_token
      @current_account = Account.find_by_web_clip_token(token) || Account.find_by_api_token(token)
      return if @current_account

      render json: { error: "認証に失敗しました。" }, status: :unauthorized
    end

    def clip_params
      params.permit(:html, :url, :title, :plain)
    end

    def clip_payload_present?
      clip_params[:html].present? || clip_params[:plain].present?
    end
  end
end
