# frozen_string_literal: true

# メモ一覧サイドバー: ディレクトリまたはタグで絞り込み、ナビ一覧を表示
module MemoSidebar
  extend ActiveSupport::Concern

  included do
    before_action :set_memo_directory_nav_context
    before_action :load_sidebar_memos_list
  end

  # ドラフトで memo_directory_id が変わったあと、一覧サイドバーをメモの保存先に合わせ直す
  def refresh_memo_sidebar_directory_context!
    @sidebar_view = "directory"
    @current_memo_directory = @memo.memo_directory
    load_sidebar_memos_list
  end

  private

  def set_memo_directory_nav_context
    @memo_directories_for_nav = policy_scope(MemoDirectory).nav_ordered
    @tags_for_nav = Tag.order(:name)
    @sidebar_view = params[:sidebar_view] == "tag" ? "tag" : "directory"

    @current_memo_directory =
      if instance_variable_defined?(:@memo) && @memo&.persisted? && %w[show edit update draft destroy].include?(action_name)
        @memo.memo_directory
      elsif params[:memo_directory_id].present?
        policy_scope(MemoDirectory).find_by(id: params[:memo_directory_id]) || MemoDirectory.root
      else
        MemoDirectory.root
      end

    @current_tag =
      if @sidebar_view == "tag" && params[:tag_id].present?
        Tag.find_by(id: params[:tag_id])
      end
  end

  def load_sidebar_memos_list
    return unless %w[memos memo_directories tags].include?(controller_path)

    base = policy_scope(Memo).order(updated_at: :desc).includes(:tags, :memo_directory, :account)

    @memos =
      if @sidebar_view == "tag"
        if @current_tag
          base.joins(:memo_tags).where(memo_tags: { tag_id: @current_tag.id }).distinct
        else
          base.none
        end
      else
        base.where(memo_directory_id: @current_memo_directory.id)
      end
  end
end
