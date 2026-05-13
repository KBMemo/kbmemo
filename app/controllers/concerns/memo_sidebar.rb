# frozen_string_literal: true

# メモ一覧サイドバー: 現在ディレクトリのメモ一覧とナビ用ディレクトリ一覧
module MemoSidebar
  extend ActiveSupport::Concern

  included do
    before_action :set_memo_directory_nav_context
    before_action :load_sidebar_memos_list
  end

  private

  def set_memo_directory_nav_context
    @memo_directories_for_nav = MemoDirectory.nav_ordered
    @current_memo_directory =
      if instance_variable_defined?(:@memo) && @memo&.persisted? && %w[show edit update draft destroy].include?(action_name)
        @memo.memo_directory
      elsif params[:memo_directory_id].present?
        MemoDirectory.find_by(id: params[:memo_directory_id]) || MemoDirectory.root
      else
        MemoDirectory.root
      end
  end

  def load_sidebar_memos_list
    return unless %w[memos memo_directories].include?(controller_path)

    @memos = Memo.order(updated_at: :desc).includes(:tags, :memo_directory)
      .where(memo_directory_id: @current_memo_directory.id)
  end
end
