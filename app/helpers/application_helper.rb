module ApplicationHelper
  def memos_wide_layout?
    %w[memos memo_directories].include?(controller.controller_path)
  end

  def new_memo_path_with_current_directory
    return new_memo_path unless defined?(@current_memo_directory) && @current_memo_directory
    return new_memo_path if @current_memo_directory.root?

    new_memo_path(memo_directory_id: @current_memo_directory.id)
  end
end
