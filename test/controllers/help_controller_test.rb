# frozen_string_literal: true

require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @notebook = notebooks(:one)
    @notebook.update_columns(
      slug: HelpNotebook::DEFAULT_SLUG,
      publication_kind: Notebook.publication_kinds[:manual],
      published_at: Time.current
    )
    memos(:one).update_columns(visibility: Memo.visibilities[:public_everyone])
    memos(:two).update_columns(visibility: Memo.visibilities[:public_everyone])
  end

  test "guest can view help index" do
    sign_out
    get help_url
    assert_response :success
    assert_includes response.body, @notebook.title
    assert_includes response.body, memos(:one).title
  end

  test "guest can view help memo by slug" do
    sign_out
    get help_memo_url(memo_slug: memos(:two).slug)
    assert_response :success
    assert_includes response.body, memos(:two).title
  end

  test "help returns not found when notebook unpublished" do
    sign_out
    @notebook.update_columns(published_at: nil)
    get help_url
    assert_response :not_found
  end
end
