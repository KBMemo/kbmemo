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
    if dialog_request?
      @lock_parent = @memo_directory.parent.present?
      render partial: "dialog_form", layout: false
      nil
    end
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
        if dialog_request?
          @lock_parent = false
          render_dialog_form_stream(status: :unprocessable_entity)
        else
          render :new, status: :unprocessable_entity
        end
        return
      end
      @memo_directory.parent = parent
    end
    authorize @memo_directory
    if @memo_directory.save
      if params[:board_picker].present?
        render turbo_stream: turbo_stream.update(
          "board_directory_picker",
          partial: "boards/directory_picker_field",
          locals: { selected_directory: @memo_directory }
        )
      elsif dialog_request?
        flash.now[:notice] = "ディレクトリを作成しました。"
        render_sidebar_refresh_stream
      else
        redirect_to memo_directories_path, notice: "ディレクトリを作成しました。"
      end
    else
      prepare_parent_options
      if dialog_request?
        @lock_parent = @memo_directory.parent.present?
        render_dialog_form_stream(status: :unprocessable_entity)
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def edit
    authorize @memo_directory
    prepare_parent_options
    if dialog_request?
      render partial: "dialog_form", layout: false
      nil
    end
  end

  def update
    authorize @memo_directory
    attrs = memo_directory_params_update
    attrs = attrs.to_h if attrs.respond_to?(:to_h)
    attrs.delete("parent_id") if @memo_directory.root?
    attrs = normalize_parent_id_param(attrs) if attrs.key?("parent_id")

    parent_changing = !@memo_directory.root? &&
      attrs.key?("parent_id") &&
      attrs["parent_id"].to_i != @memo_directory.parent_id

    if parent_changing && !@memo_directory.reparentable?
      flash.now[:alert] = "このディレクトリは移動できません。"
      prepare_parent_options
      if dialog_request?
        render_dialog_form_stream(status: :unprocessable_entity)
      else
        render :edit, status: :unprocessable_entity
      end
      return
    end

    if parent_changing && attrs["parent_id"].present? &&
        !policy_scope(MemoDirectory).exists?(id: attrs["parent_id"].to_i)
      @memo_directory.assign_attributes(attrs)
      @memo_directory.errors.add(:parent_id, "指定できない親です")
      prepare_parent_options
      if dialog_request?
        render_dialog_form_stream(status: :unprocessable_entity)
      else
        render :edit, status: :unprocessable_entity
      end
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
          if dialog_request?
            flash.now[:alert] = "ディレクトリは更新しましたが、Git 上のファイル移動に失敗しました: #{e.message}"
            render_sidebar_refresh_stream
          else
            flash[:alert] = "ディレクトリは更新しましたが、Git 上のファイル移動に失敗しました: #{e.message}"
            redirect_to memo_directories_path
          end
          return
        end
      end

      if dialog_request?
        flash.now[:notice] = "ディレクトリを更新しました。"
        render_sidebar_refresh_stream
      else
        redirect_to memo_directories_path, notice: "ディレクトリを更新しました。"
      end
    else
      prepare_parent_options
      if dialog_request?
        render_dialog_form_stream(status: :unprocessable_entity)
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end

  def destroy
    if @memo_directory.root?
      skip_authorization
      respond_to_destroy_blocked("ルートは削除できません。")
      return
    end
    unless @memo_directory.deletable?
      skip_authorization
      respond_to_destroy_blocked(delete_blocked_message(@memo_directory))
      return
    end
    authorize @memo_directory

    redirect_after_sidebar_delete = sidebar_delete_redirect_url if sidebar_delete_current_directory?

    @memo_directory.destroy!

    if sidebar_request?
      flash.now[:notice] = "ディレクトリを削除しました。"
      response.headers["X-Sidebar-Redirect"] = redirect_after_sidebar_delete if redirect_after_sidebar_delete
      render_sidebar_refresh_stream
    else
      redirect_to memo_directories_path, notice: "ディレクトリを削除しました。", status: :see_other
    end
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError
    respond_to_destroy_blocked("このディレクトリは削除できません。関連するデータが残っています。")
  end

  private

  def dialog_request?
    params[:dialog].present?
  end

  def sidebar_request?
    params[:sidebar].present?
  end

  def sidebar_delete_current_directory?
    sidebar_request? &&
      params[:current_memo_directory_id].present? &&
      params[:current_memo_directory_id].to_i == @memo_directory.id
  end

  def sidebar_delete_redirect_url
    fallback = @memo_directory.delete_navigation_fallback
    if params[:open_memo_id].present?
      memo = policy_scope(Memo).find_by(id: params[:open_memo_id])
      if memo
        q = {}
        q[:memo_directory_id] = fallback.id unless fallback.root?
        return memo_path(memo, q)
      end
    end

    fallback.root? ? memos_path : memos_path(memo_directory_id: fallback.id)
  end

  def respond_to_destroy_blocked(message)
    if sidebar_request?
      flash.now[:alert] = message
      render_sidebar_refresh_stream(status: :unprocessable_entity)
    else
      redirect_to memo_directories_path, alert: message, status: :see_other
    end
  end

  def render_sidebar_refresh_stream(status: :ok)
    render turbo_stream: turbo_stream.replace("memos_list_panel", partial: "memos/list_panel"), status: status
  end

  def render_dialog_form_stream(status: :ok)
    render turbo_stream: turbo_stream.update("memo_directory_dialog_body", partial: "memo_directories/dialog_form"),
           status: status
  end

  def delete_blocked_message(directory)
    if directory.memos_in_subtree?
      "メモが残っているディレクトリは削除できません。"
    elsif directory.boards_in_subtree?
      "ボードの保存先に指定されているディレクトリは削除できません。"
    elsif directory.children.exists?
      "子ディレクトリが残っているため削除できません。"
    else
      "このディレクトリは削除できません。"
    end
  end

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

  # 空の parent_id は最上位（ルート）直下を意味する
  def normalize_parent_id_param(attrs)
    attrs = attrs.dup
    attrs["parent_id"] = attrs["parent_id"].presence || MemoDirectory.root.id
    attrs
  end
end
