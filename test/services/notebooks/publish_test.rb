# frozen_string_literal: true

require "test_helper"

class NotebooksPublishTest < ActiveSupport::TestCase
  test "publish sets published_at for blog" do
    notebook = notebooks(:two)
    notebook.update_columns(published_at: nil)

    Notebooks::Publish.call(notebook: notebook)
    assert notebook.reload.published?
  end

  test "publish rejects notes kind" do
    notebook = notebooks(:one)
    notebook.update_columns(publication_kind: Notebook.publication_kinds[:notes], published_at: nil)

    assert_raises(Notebooks::Error) { Notebooks::Publish.call(notebook: notebook) }
  end
end
