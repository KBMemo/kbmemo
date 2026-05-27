# frozen_string_literal: true

require "test_helper"

class NotebooksExportTest < ActiveSupport::TestCase
  setup do
    @target = Rails.root.join("tmp", "notebook_export_test", SecureRandom.hex(4))
    @notebook = notebooks(:one)
  end

  teardown do
    FileUtils.rm_rf(@target)
  end

  test "exports notebook tree to adoc files" do
    result = Notebooks::Export.call(notebook: @notebook, target_root: @target)

    assert_operator result.written, :>=, 2
    assert result.paths.all? { |path| path.end_with?(".adoc") || path.include?("would write") }
    exported = @target.glob("**/*.adoc")
    assert exported.any?
    content = exported.first.read
    assert_includes content, "---"
    assert_includes content, memos(:one).title
  end

  test "dry run does not write files" do
    result = Notebooks::Export.call(notebook: @notebook, target_root: @target, dry_run: true)

    assert_operator result.written, :>=, 1
    assert_empty @target.glob("**/*")
  end
end
