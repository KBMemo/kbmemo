# frozen_string_literal: true

class MemoSvgSourcesController < ApplicationController
  layout "svg_editor"

  before_action :set_memo
  before_action :set_index

  after_action :verify_authorized

  def edit
    authorize @memo, :update?
    @source = MemoSvgSourceBlocks.fetch(@memo.body, index: @index)
  rescue MemoSvgSourceBlocks::NotFound
    redirect_to memo_path(@memo), alert: "SVG ソースブロックが見つかりません。"
  end

  def update
    authorize @memo, :update?
    @memo.body = MemoSvgSourceBlocks.replace(
      @memo.body,
      index: @index,
      new_source: params.require(:source)
    )
    @memo.save!(validate: false)
    @memo.touch
    redirect_to memo_path(@memo), notice: "SVG ソースを更新しました。"
  rescue MemoSvgSourceBlocks::NotFound
    redirect_to memo_path(@memo), alert: "SVG ソースブロックが見つかりません。"
  rescue MemoAssets::InvalidFile, MemoSvgSourceBlocks::Error => e
    @source = params[:source]
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_entity
  end

  private

  def set_memo
    @memo = policy_scope(Memo).find(params[:id])
  end

  def set_index
    @index = params[:index].to_i
  end
end
