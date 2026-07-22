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
    assert_select "input#account_nickname[aria-invalid='true'][aria-describedby='account-nickname-help account_nickname_error']"
    assert_select "#account_nickname_error", text: /too long/
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

  test "signed-in user sees clip bookmarklet setup on profile" do
    get edit_profile_url
    assert_response :success
    assert_includes response.body, "clip-bookmarklet-setup"
    assert_includes response.body, "kbmemo に保存"
    assert_includes response.body, "kbmemo にコピー"
    assert_not_includes response.body, "clip-bookmarklet-api-token"
  end

  test "signed-in user can generate and revoke account api token" do
    account = accounts(:one)
    assert_not account.api_token_configured?

    post api_token_profile_url
    assert_response :success
    assert account.reload.api_token_configured?
    assert_match(/kbmemo_/, response.body)
    assert_select "section#account-api-token[data-controller~='scroll-into-view'][tabindex='-1']"
    assert_no_match(/scrollIntoView/, response.body)

    delete api_token_profile_url
    assert_redirected_to edit_profile_path
    assert_not account.reload.api_token_configured?
  end

  test "signed-in user can generate and revoke web clip token" do
    account = accounts(:one)
    assert_not account.web_clip_token_configured?

    post web_clip_token_profile_url

    assert_response :success
    assert account.reload.web_clip_token_configured?
    assert_match(/kbmemo_clip_/, response.body)
    assert_includes response.body, "clip-bookmarklet-setup"
    assert_includes response.body, "kbmemo に保存"
    assert_includes response.body, "javascript:"
    assert_select "section#web-clip-token[data-controller~='scroll-into-view'][tabindex='-1']"

    delete web_clip_token_profile_url
    assert_redirected_to edit_profile_path
    assert_not account.reload.web_clip_token_configured?
  end

  test "signed-in user can generate and reveal tsuzura api token" do
    account = accounts(:one)
    assert_not account.tsuzura_api_token_configured?

    post tsuzura_api_token_profile_url
    assert_response :success
    assert account.reload.tsuzura_api_token_configured?
    assert_match(/tsuzura_/, response.body)
    assert_select "section#tsuzura-cli-token[data-controller~='scroll-into-view'][tabindex='-1']"
    assert_no_match(/scrollIntoView/, response.body)
  end
end
