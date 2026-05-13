# frozen_string_literal: true

class TagsController < ApplicationController
  include MemoSidebar
  helper MemosHelper

  before_action :set_tag, only: %i[edit update destroy]

  def index
    @tags = Tag.order(:name)
    @tag_counts = MemoTag.group(:tag_id).count
  end

  def edit
  end

  def update
    if @tag.update(tag_params)
      redirect_to tags_path, notice: "タグを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @tag.memo_tags.exists?
      redirect_to tags_path, alert: "メモに紐付いているタグは削除できません。先に統合するか、各メモから外してください。", status: :see_other
      return
    end
    @tag.destroy!
    redirect_to tags_path, notice: "タグを削除しました。", status: :see_other
  end

  def merge_form
    @tags_for_select = Tag.order(:name)
    @source_tag = Tag.find_by(id: params[:from_tag_id])
  end

  def merge
    source = Tag.find_by(id: params[:source_tag_id])
    target = Tag.find_by(id: params[:target_tag_id])

    if source.nil? || target.nil?
      redirect_to merge_tags_path(from_tag_id: params[:source_tag_id]), alert: "統合元・統合先のタグを選んでください。", status: :see_other
      return
    end
    if source.id == target.id
      redirect_to merge_tags_path(from_tag_id: source.id), alert: "統合元と統合先に同じタグは選べません。", status: :see_other
      return
    end

    label = source.name
    source.merge_into!(target)
    redirect_to tags_path, notice: "「#{label}」を「#{target.name}」へ統合しました。"
  rescue ArgumentError => e
    redirect_to merge_tags_path(from_tag_id: params[:source_tag_id]), alert: e.message, status: :see_other
  end

  private

  def set_tag
    @tag = Tag.find(params[:id])
  end

  def tag_params
    params.require(:tag).permit(:name)
  end
end
