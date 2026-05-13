# frozen_string_literal: true

class MemoDirectoriesController < ApplicationController
  include MemoSidebar
  helper MemosHelper

  before_action :set_memo_directory, only: %i[edit update destroy]

  def index
    @memo_directories = MemoDirectory.nav_ordered
  end

  def new
    @memo_directory = MemoDirectory.new
  end

  def create
    @memo_directory = MemoDirectory.new(memo_directory_params_create)
    if @memo_directory.save
      redirect_to memo_directories_path, notice: "ディレクトリを作成しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @memo_directory.update(memo_directory_params_update)
      redirect_to memo_directories_path, notice: "ディレクトリを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @memo_directory.root?
      redirect_to memo_directories_path, alert: "ルートは削除できません。", status: :see_other
      return
    end
    if @memo_directory.memos.exists?
      redirect_to memo_directories_path, alert: "メモが残っているディレクトリは削除できません。", status: :see_other
      return
    end
    @memo_directory.destroy
    redirect_to memo_directories_path, notice: "ディレクトリを削除しました。", status: :see_other
  end

  private

  def set_memo_directory
    @memo_directory = MemoDirectory.find(params[:id])
  end

  def memo_directory_params_create
    params.require(:memo_directory).permit(:path_segment, :label)
  end

  def memo_directory_params_update
    params.require(:memo_directory).permit(:label)
  end
end
