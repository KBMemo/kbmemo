# frozen_string_literal: true

module Api
  module V1
    class MeController < BaseController
      def show
        render json: {
          id: @current_account.id,
          email: @current_account.email,
          token_type: "clip_api_token",
          scopes: []
        }
      end
    end
  end
end
