# frozen_string_literal: true

module Api
  module V1
    module Memos
      class ExportController < BaseController
        def index
          authorize Memo, :index?

          scope = export_scope.order(updated_at: :asc, id: :asc)
          limit = pagination_limit(default: 100)
          scope = apply_cursor(scope)
          memos = scope.limit(limit + 1).to_a
          has_more = memos.size > limit
          memos = memos.first(limit)

          render json: {
            memos: memos.map { |memo| memo_json(memo) },
            pagination: {
              limit: limit,
              next_cursor: has_more ? encode_cursor(memos.last) : nil,
              has_more: has_more
            }
          }
        end

        def deletions
          render_api_error(
            code: "not_implemented",
            message: "削除フィードは未実装です。",
            status: :not_implemented
          )
        end

        private

        def export_scope
          scope = apply_draft_scope(policy_scope_memos)
          if (since = parse_time_param(params[:updated_since]))
            scope = scope.where("memos.updated_at >= ?", since)
          end
          scope
        end

        def apply_cursor(scope)
          cursor = decode_cursor(params[:cursor])
          return scope if cursor.blank?

          scope.where(
            "(memos.updated_at > ?) OR (memos.updated_at = ? AND memos.id > ?)",
            cursor[:updated_at],
            cursor[:updated_at],
            cursor[:id]
          )
        end

        def encode_cursor(memo)
          payload = { updated_at: memo.updated_at.utc.iso8601, id: memo.id }
          Base64.urlsafe_encode64(payload.to_json, padding: false)
        end

        def decode_cursor(raw)
          return nil if raw.blank?

          payload = JSON.parse(Base64.urlsafe_decode64(raw.to_s))
          {
            updated_at: Time.iso8601(payload.fetch("updated_at")),
            id: payload.fetch("id")
          }
        rescue ArgumentError, JSON::ParserError, KeyError, TypeError
          nil
        end
      end
    end
  end
end
