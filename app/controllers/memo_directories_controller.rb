# frozen_string_literal: true

class MemoDirectoriesController < ApplicationController
  include MemoSidebar
  helper MemosHelper

  after_action :verify_authorized

  before_action :set_memo_directory, only: %i[edit update destroy]
  before_action :prepare_parent_options, only: %i[new edit]

  def index
    authorize MemoDirectory
    @memo_directories = policy_scope(MemoDirectory).nav_ordered
  end

  def new
    authorize MemoDirectory
    @memo_directory = MemoDirectory.new
    if params[:parent_id].present?
      parent = policy_scope(MemoDirectory).find_by(id: params[:parent_id])
      @memo_directory.parent = parent if parent
    end
    prepare_parent_options
  end

  def create
    attrs = memo_directory_params_create.to_h
    parent_id = attrs.delete("parent_id")
    @memo_directory = MemoDirectory.new(attrs)
    if parent_id.present?
      parent = policy_scope(MemoDirectory).find_by(id: parent_id)
      unless parent
        @memo_directory.errors.add(:parent_id, "指定できない親です")
        prepare_parent_options
        render :new, status: :unprocessable_entity
        return
      end
      @memo_directory.parent = parent
    else
      @memo_directory.parent ||= MemoDirectory::UserSpace.default_home_directory(rodauth.rails_account.id)
    end
    authorize @memo_directory
    if @memo_directory.save
      redirect_to memo_directories_path, notice: "ディレクトリを作成しました。"
    else
      prepare_parent_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @memo_directory
    prepare_parent_options
  end

  def update
    authorize @memo_directory
    attrs = memo_directory_params_update
    attrs = attrs.to_h if attrs.respond_to?(:to_h)
    attrs.delete("parent_id") if @memo_directory.root?

    parent_changing = !@memo_directory.root? &&
      attrs.key?("parent_id") &&
      attrs["parent_id"].present? &&
      attrs["parent_id"].to_i != @memo_directory.parent_id

    if parent_changing && !@memo_directory.reparentable?
      flash.now[:alert] = "このディレクトリは移動できません。"
      prepare_parent_options
      render :edit, status: :unprocessable_entity
      return
    end

    if parent_changing && attrs["parent_id"].present? &&
        !policy_scope(MemoDirectory).exists?(id: attrs["parent_id"].to_i)
      @memo_directory.assign_attributes(attrs)
      @memo_directory.errors.add(:parent_id, "指定できない親です")
      prepare_parent_options
      render :edit, status: :unprocessable_entity
      return
    end

    repo = MemoRepository.new
    memo_ids = []
    old_paths = {}
    if parent_changing
      memo_ids = Memo.where(memo_directory_id: @memo_directory.subtree_directory_ids).pluck(:id)
      Memo.where(id: memo_ids).includes(:memo_directory).find_each do |m|
        old_paths[m.id] = repo.relative_path_for(m).to_s
      end
    end

    if @memo_directory.update(attrs)
      @memo_directory.cascade_path_refresh! if parent_changing

      if parent_changing && memo_ids.any?
        begin
          Memo.where(id: memo_ids).includes(:memo_directory).find_each do |m|
            old = old_paths[m.id]
            nxt = repo.relative_path_for(m)
            repo.relocate_file!(from_relative: old, to_relative: nxt) if old.present? && old != nxt
          end
        rescue MemoRepository::Error => e
          flash[:alert] = "ディレクトリは更新しましたが、Git 上のファイル移動に失敗しました: #{e.message}"
          redirect_to memo_directories_path
          return
        end
      end

      redirect_to memo_directories_path, notice: "ディレクトリを更新しました。"
    else
      prepare_parent_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @memo_directory.root?
      skip_authorization
      redirect_to memo_directories_path, alert: "ルートは削除できません。", status: :see_other
      return
    end
    authorize @memo_directory
    unless @memo_directory.deletable?
      redirect_to memo_directories_path, alert: "このディレクトリは削除できません。", status: :see_other
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

  def prepare_parent_options
    dirs = policy_scope(MemoDirectory).nav_ordered.to_a
    if @memo_directory&.persisted?
      ex = @memo_directory.subtree_directory_ids
      dirs.reject! { |d| ex.include?(d.id) }
    end
    @memo_directory_parent_options = dirs
  end

  def set_memo_directory
    @memo_directory = policy_scope(MemoDirectory).find(params[:id])
  end

  def memo_directory_params_create
    params.require(:memo_directory).permit(:path_segment, :label, :parent_id)
  end

  def memo_directory_params_update
    params.require(:memo_directory).permit(:label, :parent_id)
  end
end
