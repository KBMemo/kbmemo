# frozen_string_literal: true

# メモ一覧サイドバー: 履歴・検索・ディレクトリ・タグで表示対象を絞り込む
module MemoSidebar
  extend ActiveSupport::Concern

  SIDEBAR_MEMO_PAGE_SIZE = 15

  included do
    before_action :set_memo_directory_nav_context
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
      h[:tag_ids] = @current_tags.map(&:id) if @current_tags.any?
      h[:excluded_tag_ids] = @excluded_tags.map(&:id) if @excluded_tags.any?
    elsif @sidebar_view == "history"
      h[:sidebar_view] = "history"
    elsif @sidebar_view == "directory"
      h[:sidebar_view] = "directory"
      h[:memo_directory_id] = @current_memo_directory.id if @current_memo_directory && !@current_memo_directory.root?
    end
    h
  end

  private

  def set_memo_directory_nav_context
    @memo_directories_for_nav = policy_scope(MemoDirectory).nav_ordered
    visible_memo_ids = policy_scope(Memo).select(:id)
    @tags_for_nav = Tag.joins(:memo_tags)
      .where(memo_tags: { memo_id: visible_memo_ids })
      .distinct
      .order(:name)
    @sidebar_view = sidebar_view_from_params
    @memo_search_query = @sidebar_view == "search" ? params[:q].to_s.strip.presence : nil

    @current_memo_directory =
      if params[:memo_directory_id].present?
        policy_scope(MemoDirectory).find_by(id: params[:memo_directory_id]) || MemoDirectory.root
      else
        MemoDirectory.root
      end

    requested_tag_ids = (Array(params[:tag_ids]) + [ params[:tag_id] ]).filter_map do |id|
      Integer(id, exception: false)
    end.uniq
    @current_tags =
      if @sidebar_view == "tag" && requested_tag_ids.any?
        @tags_for_nav.where(id: requested_tag_ids).to_a.sort_by { |tag| requested_tag_ids.index(tag.id) }
      else
        []
      end
    requested_excluded_tag_ids = Array(params[:excluded_tag_ids]).filter_map do |id|
      Integer(id, exception: false)
    end.uniq - @current_tags.map(&:id)
    @excluded_tags =
      if @sidebar_view == "tag" && requested_excluded_tag_ids.any?
        @tags_for_nav.where(id: requested_excluded_tag_ids).to_a.sort_by do |tag|
          requested_excluded_tag_ids.index(tag.id)
        end
      else
        []
      end
    @current_tag = @current_tags.first

    @nav_open_directory_ids = Array(params[:nav_open_directory_ids]).filter_map do |id|
      Integer(id, exception: false)
    end
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
      if @current_tags.any? || @excluded_tags.any?
        filtered = base
        tag_ids = @current_tags.map(&:id)
        if tag_ids.any?
          matching_ids = policy_scope(Memo)
            .joins(:memo_tags)
            .where(memo_tags: { tag_id: tag_ids })
            .group("memos.id")
            .having("COUNT(DISTINCT memo_tags.tag_id) = ?", tag_ids.size)
            .select(:id)
          filtered = filtered.where(id: matching_ids)
        end
        if @excluded_tags.any?
          excluded_ids = MemoTag.where(tag_id: @excluded_tags.map(&:id)).select(:memo_id)
          filtered = filtered.where.not(id: excluded_ids)
        end
        filtered
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
