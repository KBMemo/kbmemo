# frozen_string_literal: true

# メモ一覧サイドバー: ディレクトリまたはタグで絞り込み、ナビ一覧を表示
module MemoSidebar
  extend ActiveSupport::Concern

  SIDEBAR_MEMO_PAGE_SIZE = 15

  included do
    before_action :set_memo_directory_nav_context
    before_action :redirect_memo_tag_sidebar_to_memo_tag, if: :memo_show_or_edit_action?
    before_action :load_sidebar_memos_list
  end

  # ディレクトリ / タグ切り替え後も一覧・編集の文脈を保つクエリ（ハッシュ）
  def memo_sidebar_nav_query
    h = {}
    if @sidebar_view == "search"
      h[:sidebar_view] = "search"
      h[:q] = @memo_search_query if @memo_search_query.present?
    elsif @sidebar_view == "tag"
      h[:sidebar_view] = "tag"
      tid = (@current_tag&.id || params[:tag_id]).presence
      h[:tag_id] = tid if tid
    elsif @sidebar_view == "history"
      h[:sidebar_view] = "history"
    elsif @sidebar_view == "directory"
      h[:sidebar_view] = "directory"
      h[:memo_directory_id] = @current_memo_directory.id if @current_memo_directory && !@current_memo_directory.root?
    end
    h
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

    @all_memos_total_count = if rodauth.rails_account
      Memo.where(account_id: rodauth.rails_account.id).count
    else
      policy_scope(Memo).count
    end
    @sidebar_memos_scope = build_sidebar_memos_scope
    @sidebar_memos_scope_total_count = @sidebar_memos_scope.count
    load_sidebar_memos_page(offset: 0)
  end

  def build_sidebar_memos_scope
    base = policy_scope(Memo).order(updated_at: :desc).includes(:tags, :memo_directory, :account)

    case @sidebar_view
    when "search"
      @memo_search_query.present? ? base.search_text(@memo_search_query) : base.none
    when "tag"
      if @current_tag
        ids = policy_scope(Memo).joins(:memo_tags).where(memo_tags: { tag_id: @current_tag.id }).distinct.pluck(:id)
        base.where(id: ids)
      else
        base.none
      end
    when "history"
      history = MemoViewHistory.recent_history(rodauth.rails_account, scope: base.unscope(:order))
      @memo_viewed_at_by_id = history.viewed_at_by_memo_id
      history.memos
    else
      base.where(memo_directory_id: @current_memo_directory.id)
    end
  end

  def load_sidebar_memos_page(offset:)
    page_size = SIDEBAR_MEMO_PAGE_SIZE
    batch = @sidebar_memos_scope.offset(offset).limit(page_size + 1).to_a
    @memos = batch.first(page_size)
    @sidebar_memo_list_next_offset = offset + @memos.size
    @sidebar_memos_has_more = batch.size > page_size &&
      @sidebar_memo_list_next_offset < @sidebar_memos_scope_total_count
  end

  def sidebar_view_from_params
    case params[:sidebar_view].to_s
    when "tag" then "tag"
    when "search" then "search"
    when "history" then "history"
    when "directory" then "directory"
    else
      params[:memo_directory_id].present? ? "directory" : "history"
    end
  end
end
