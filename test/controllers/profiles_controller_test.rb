# frozen_string_literal: true

require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "guest cannot edit profile" do
    sign_out
    get edit_profile_url
    assert_response :redirect
    assert_match %r{/login}, @response.redirect_url
  end

  test "signed-in user can update nickname" do
    account = accounts(:one)
    assert_equal "Freddie", account.nickname

    patch profile_url, params: { account: { nickname: "  Mercury  " } }

    assert_redirected_to edit_profile_url
    assert_equal "Mercury", account.reload.nickname
  end

  test "signed-in user sees validation errors" do
    patch profile_url, params: { account: { nickname: "x" * 41 } }

    assert_response :unprocessable_entity
    assert_includes response.body, "too long"
  end

  test "signed-in user can save and clear openai api key" do
    account = accounts(:one)

    patch profile_url, params: { account: { openai_api_key: "sk-test-key-123" } }
    assert_redirected_to edit_profile_path
    assert account.reload.openai_api_key_configured?

    patch profile_url, params: { account: { clear_openai_api_key: "1" } }
    assert_redirected_to edit_profile_path
    assert_not account.reload.openai_api_key_configured?
  end

  test "signed-in user can generate and revoke clip api token" do
    account = accounts(:one)
    assert_not account.clip_api_token_configured?

    post clip_api_token_profile_url
    assert_redirected_to edit_profile_path
    assert account.reload.clip_api_token_configured?
    assert flash[:clip_api_token].start_with?("kbmemo_")

    delete clip_api_token_profile_url
    assert_redirected_to edit_profile_path
    assert_not account.reload.clip_api_token_configured?
  end
end
