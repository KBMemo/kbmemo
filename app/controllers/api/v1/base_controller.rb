# frozen_string_literal: true

module Api
  module V1
    class BaseController < Api::BaseController
      private

      def authenticate_clip_api_token!
        @current_account = Account.find_by_clip_api_token(bearer_token)
        return if @current_account

        render_api_error(code: "unauthorized", message: "認証に失敗しました。", status: :unauthorized)
      end

      def user_not_authorized
        render_api_error(code: "forbidden", message: "権限がありません。", status: :forbidden)
      end

      def render_api_error(code:, message:, status:, details: nil)
        payload = { error: { code: code, message: message } }
        payload[:error][:details] = details if details.present?
        render json: payload, status: status
      end

      def render_stale_memo(memo)
        render json: {
          error: {
            code: "stale_memo",
            message: "メモは他で更新されています",
            current: Api::V1::MemoSerializer.new(memo, view_context: self).as_json
          }
        }, status: :conflict
      end

      def render_validation_errors(record)
        details = record.errors.map do |error|
          { field: error.attribute.to_s, message: error.full_message }
        end
        render_api_error(
          code: "validation_error",
          message: "入力内容に問題があります。",
          status: :unprocessable_entity,
          details: details
        )
      end

      def render_not_found(message = "メモが見つかりません。")
        render_api_error(code: "not_found", message: message, status: :not_found)
      end

      def policy_scope_memos
        policy_scope(Memo).includes(:tags, :memo_directory)
      end

      def find_memo!(memo_ref)
        key = memo_ref.to_s
        scope = policy_scope_memos
        if key.match?(Memo::UID_FORMAT)
          scope.find_by!(uid: key.upcase)
        else
          scope.find(key)
        end
      end

      def parse_time_param(value)
        return nil if value.blank?

        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def expected_updated_at
        parse_time_param(params[:updated_at]) || parse_time_param(request.headers["If-Unmodified-Since"])
      end

      def requested_fields
        fields = params[:fields].to_s.split(",").map(&:strip).reject(&:blank?)
        fields.presence
      end

      def include_drafts?
        ActiveModel::Type::Boolean.new.cast(params[:include_drafts])
      end

      def apply_draft_scope(scope)
        return scope if include_drafts?

        scope.where.not(file_committed_at: nil)
      end

      def pagination_limit(default: 50, max: 200)
        value = params[:limit].to_i
        value = default if value <= 0
        [ value, max ].min
      end

      def pagination_offset
        value = params[:offset].to_i
        value.negative? ? 0 : value
      end

      def memo_json(memo, fields: requested_fields, summary: false)
        Api::V1::MemoSerializer.new(
          memo,
          fields: fields,
          summary: summary,
          view_context: self
        ).as_json
      end
    end
  end
end
