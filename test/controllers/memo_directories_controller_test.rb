# frozen_string_literal: true

require "test_helper"

class MemoDirectoriesControllerTest < ActionDispatch::IntegrationTest
  test "index lists directories" do
    get memo_directories_url
    assert_response :success
    assert_includes response.body, "ルート"
    assert_includes response.body, "work"
  end

  test "create directory" do
    assert_difference("MemoDirectory.count", 1) do
      post memo_directories_url, params: { memo_directory: { path_segment: "ideas", label: "アイデア" } }
    end
    assert_redirected_to memo_directories_url
    d = MemoDirectory.find_by(path_segment: "ideas")
    assert_equal "アイデア", d.label
  end

  test "cannot delete root" do
    root = memo_directories(:root)
    assert_no_difference("MemoDirectory.count") do
      delete memo_directory_url(root)
    end
    assert_redirected_to memo_directories_url
  end
end
