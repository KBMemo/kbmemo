# frozen_string_literal: true

require "test_helper"

class MemoDirectorySystemSpaceTest < ActiveSupport::TestCase
  test "ensure_buckets creates system docs and help" do
    MemoDirectory::SystemSpace.ensure_buckets!

    assert MemoDirectory.exists?(full_path: "system")
    assert MemoDirectory.exists?(full_path: "system/docs")
    assert MemoDirectory.exists?(full_path: "system/help")
  end

  test "ensure_subdirectory creates nested path under system docs" do
    dir = MemoDirectory::SystemSpace.ensure_subdirectory!("docs", "architecture")

    assert_equal "system/docs/architecture", dir.full_path
    assert dir.under_system_space?
  end

  test "ensure_buckets is idempotent" do
    MemoDirectory::SystemSpace.ensure_buckets!
    ids = %w[system system/docs system/help].map { |fp| MemoDirectory.find_by!(full_path: fp).id }

    MemoDirectory::SystemSpace.ensure_buckets!

    assert_equal ids, %w[system system/docs system/help].map { |fp| MemoDirectory.find_by!(full_path: fp).id }
  end
end
