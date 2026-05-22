# frozen_string_literal: true

# メモ一覧サイドバー: ディレクトリまたはタグで絞り込み、ナビ一覧を表示
module MemoSidebar
  extend ActiveSupport::Concern

  included do
    before_action :set_memo_directory_nav_context
    before_action :redirect_memo_tag_sidebar_to_memo_tag, if: :memo_show_or_edit_action?
    before_action :load_sidebar_memos_list
  end

  private

  def memo_show_or_edit_action?
    %w[show edit].include?(action_name)
  end

  def set_memo_directory_nav_context
    @memo_directories_for_nav = policy_scope(MemoDirectory).nav_ordered
    @tags_for_nav = Tag.order(:name)
    @sidebar_view = sidebar_view_from_params
    @memo_search_query = @sidebar_view == "search" ? params[:q].to_s.strip.presence : nil

    @current_memo_directory =
      if params[:memo_directory_id].present?
        policy_scope(MemoDirectory).find_by(id: params[:memo_directory_id]) || MemoDirectory.root
      elsif %w[new create].include?(action_name) && instance_variable_defined?(:@memo) && @memo&.memo_directory && !@memo.memo_directory.root?
        @memo.memo_directory
      elsif memo_show_or_edit_action? && @sidebar_view == "directory" && instance_variable_defined?(:@memo) && @memo&.memo_directory && !@memo.memo_directory.root?
        @memo.memo_directory
      else
        MemoDirectory.root
      end

    @current_tag =
      if @sidebar_view == "tag"
        if params[:tag_id].present?
          Tag.find_by(id: params[:tag_id])
        elsif @memo&.persisted? && %w[show edit].include?(action_name)
          @memo.tags.order(:name).first
        end
      end

    @nav_open_directory_ids = Array(params[:nav_open_directory_ids]).filter_map do |id|
      Integer(id, exception: false)
    end
  end

  def redirect_memo_tag_sidebar_to_memo_tag
    return unless params[:sidebar_view] == "tag"
    return if params[:tag_id].present?

    tag = @memo.tags.order(:name).first
    return unless tag

    redirect_to helpers.memo_sidebar_open_memo_path(@memo, sidebar_view: "tag", tag_id: tag.id)
  end

  def load_sidebar_memos_list
    return unless %w[memos memo_directories tags].include?(controller_path)

    base = policy_scope(Memo).order(updated_at: :desc).includes(:tags, :memo_directory, :account)

    @memos =
      case @sidebar_view
      when "search"
        @memo_search_query.present? ? base.search_text(@memo_search_query) : base.none
      when "tag"
        if @current_tag
          base.joins(:memo_tags).where(memo_tags: { tag_id: @current_tag.id }).distinct
        else
          base.none
        end
      else
        base.where(memo_directory_id: @current_memo_directory.id)
      end
  end

  def sidebar_view_from_params
    case params[:sidebar_view].to_s
    when "tag" then "tag"
    when "search" then "search"
    else "directory"
    end
  end
end
