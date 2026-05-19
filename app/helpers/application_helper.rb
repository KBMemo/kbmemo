module ApplicationHelper
  def memos_wide_layout?
    %w[memos memo_directories tags].include?(controller.controller_path)
  end

  # メモ一覧サイドバーなしで、ヘッダー・本文を広幅にする画面
  def wide_content_layout?
    memos_wide_layout? || controller.controller_path.in?(%w[memo_diagrams boards])
  end

  def new_memo_path_with_current_directory
    opts = memo_sidebar_nav_query.dup
    unless defined?(@sidebar_view) && @sidebar_view == "tag"
      if defined?(@current_memo_directory) && @current_memo_directory && !@current_memo_directory.root?
        opts[:memo_directory_id] ||= @current_memo_directory.id
      end
    end
    return new_memo_path if opts.blank?

    new_memo_path(opts)
  end
end
