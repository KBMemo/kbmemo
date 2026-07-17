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
          authorize Memo, :index?

          since = parse_time_param(params[:deleted_since])
          if since.blank?
            return render_api_error(
              code: "validation_error",
              message: "deleted_since は ISO8601 形式で指定してください。",
              status: :unprocessable_entity
            )
          end

          scope = MemoDeletionRecord.where(account_id: @current_account.id)
                                    .where("deleted_at >= ?", since)
                                    .order(deleted_at: :asc, id: :asc)
          limit = pagination_limit(default: 100)
          scope = apply_deletion_cursor(scope)
          deletions = scope.limit(limit + 1).to_a
          has_more = deletions.size > limit
          deletions = deletions.first(limit)

          render json: {
            deletions: deletions.map { |record| deletion_json(record) },
            pagination: {
              limit: limit,
              next_cursor: has_more ? encode_deletion_cursor(deletions.last) : nil,
              has_more: has_more
            }
          }
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
          payload = { updated_at: memo.updated_at.utc.iso8601(6), id: memo.id }
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

        def apply_deletion_cursor(scope)
          cursor = decode_deletion_cursor(params[:cursor])
          return scope if cursor.blank?

          scope.where(
            "(deleted_at > ?) OR (deleted_at = ? AND id > ?)",
            cursor[:deleted_at],
            cursor[:deleted_at],
            cursor[:id]
          )
        end

        def encode_deletion_cursor(record)
          payload = { deleted_at: record.deleted_at.utc.iso8601(6), id: record.id }
          Base64.urlsafe_encode64(payload.to_json, padding: false)
        end

        def decode_deletion_cursor(raw)
          return nil if raw.blank?

          payload = JSON.parse(Base64.urlsafe_decode64(raw.to_s))
          {
            deleted_at: Time.iso8601(payload.fetch("deleted_at")),
            id: payload.fetch("id")
          }
        rescue ArgumentError, JSON::ParserError, KeyError, TypeError
          nil
        end

        def deletion_json(record)
          {
            id: record.memo_id,
            uid: record.memo_uid,
            deleted_at: record.deleted_at.utc.iso8601
          }
        end
      end
    end
  end
end
