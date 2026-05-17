# frozen_string_literal: true

class MemoAssetsController < ApplicationController
  before_action :set_memo

  after_action :verify_authorized

  def create
    authorize @memo, :upload_asset?
    result = MemoAssets.upload(@memo, file: params.require(:file))
    render json: result
  rescue MemoAssets::InvalidFile => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    authorize @memo, :show_asset?
    path = MemoAssets.resolve_path!(@memo, params[:filename])
    send_file path, disposition: :inline
  rescue MemoAssets::InvalidFile
    head :not_found
  end

  private

  def set_memo
    @memo = policy_scope(Memo).find(params[:id])
  end
end
