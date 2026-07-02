# frozen_string_literal: true

module Api
  module V1
    class MemosController < BaseController
      before_action :set_memo, only: %i[show update destroy]

      def index
        authorize Memo, :index?

        scope = filtered_memos.order(updated_at: :desc, id: :desc)
        total = scope.count
        limit = pagination_limit
        offset = pagination_offset
        memos = scope.offset(offset).limit(limit)

        render json: {
          memos: memos.map { |memo| memo_json(memo, summary: true) },
          pagination: {
            total: total,
            limit: limit,
            offset: offset,
            has_more: offset + memos.size < total
          }
        }
      end

      def show
        authorize @memo, :show?
        render json: memo_json(@memo)
      end

      def create
        authorize Memo.new(account: @current_account), :create?

        if create_params[:body].blank?
          render_api_error(code: "validation_error", message: "body が必要です。", status: :unprocessable_entity)
          return
        end

        memo = Api::V1::MemoWriter.new(account: @current_account).create!(create_params)
        render json: memo_json(memo), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_validation_errors(e.record)
      rescue ArgumentError => e
        render_api_error(code: "validation_error", message: e.message, status: :unprocessable_entity)
      rescue Api::V1::MemoBodyConverter::UnsupportedFormat, Api::V1::MemoBodyConverter::Error => e
        render_api_error(code: "validation_error", message: e.message, status: :unprocessable_entity)
      end

      def update
        authorize @memo, :update?

        writer = Api::V1::MemoWriter.new(account: @current_account)
        memo = writer.update!(
          @memo,
          attributes: update_params,
          expected_updated_at: expected_updated_at,
          replace: request.put?
        )
        render json: memo_json(memo)
      rescue Api::V1::MemoWriter::StaleMemo => e
        render_stale_memo(e.memo)
      rescue ActiveRecord::RecordInvalid => e
        render_validation_errors(e.record)
      rescue ArgumentError => e
        render_api_error(code: "validation_error", message: e.message, status: :unprocessable_entity)
      rescue Api::V1::MemoBodyConverter::UnsupportedFormat, Api::V1::MemoBodyConverter::Error => e
        render_api_error(code: "validation_error", message: e.message, status: :unprocessable_entity)
      end

      def destroy
        authorize @memo, :destroy?
        @memo.destroy!
        head :no_content
      end

      private

      def set_memo
        @memo = find_memo!(params[:memo_ref])
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def filtered_memos
        scope = apply_draft_scope(policy_scope_memos)
        scope = scope.search_text(params[:q]) if params[:q].present?
        scope = scope.joins(:tags).where(tags: { name: params[:tag] }) if params[:tag].present?

        if (since = parse_time_param(params[:updated_since]))
          scope = scope.where("memos.updated_at >= ?", since)
        end

        scope
      end

      def create_params
        permitted = params.permit(:title, :body, :body_format, :visibility, :commit, tags: [], properties: {})
        permitted[:commit] = ActiveModel::Type::Boolean.new.cast(permitted[:commit]) unless permitted[:commit].nil?
        permitted.to_unsafe_h.symbolize_keys
      end

      def update_params
        permitted = params.permit(:title, :body, :append_body, :body_format, :visibility, :commit, tags: [], properties: {})
        permitted[:commit] = ActiveModel::Type::Boolean.new.cast(permitted[:commit]) unless permitted[:commit].nil?
        permitted.to_unsafe_h.symbolize_keys
      end
    end
  end
end
