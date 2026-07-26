# frozen_string_literal: true

require "test_helper"

class ThemesControllerTest < ActionDispatch::IntegrationTest
  test "guest cannot access theme studio" do
    sign_out
    get theme_studio_url
    assert_response :redirect
    assert_match %r{/login}, @response.redirect_url
  end

  test "signed-in user can access theme studio" do
    get theme_studio_url
    assert_response :success
    assert_includes response.body, "テーマ作成"
    assert_includes response.body, "Design モード"
    assert_includes response.body, "AsciiDoc プリセット"
    assert_includes response.body, "data-controller=\"theme-studio\""
    assert_includes response.body, "data-controller=\"skin-studio\""
    assert_includes response.body, "本文スキン"
    assert_match(/<main[^>]*max-w-none/, response.body)
  end

  test "guest cannot fetch theme preference" do
    sign_out
    get theme_url(format: :json)
    assert_response :redirect
  end

  test "signed-in user can fetch and update theme preference" do
    get theme_url(format: :json)
    assert_response :success
    assert_equal "default", response.parsed_body["active_theme_id"]

    patch theme_url(format: :json), params: {
      active_theme_id: "dark",
      custom_themes: [
        {
          id: "custom-test",
          label: "Test",
          base_theme: "dark",
          variables: { "--kb-bg-page" => "#101010" },
          rules: []
        }
      ]
    }, as: :json

    assert_response :no_content
    assert_equal "dark", accounts(:one).reload.theme_active_id
    assert_equal 1, accounts(:one).theme_preference_payload["custom_themes"].size
  end

  test "update ignores format and theme query params without unpermitted warnings" do
    patch "#{theme_path(format: :json)}?theme=custom-query-id", params: {
      active_theme_id: "minimal",
      custom_themes: []
    }, as: :json

    assert_response :no_content
    assert_equal "minimal", accounts(:one).reload.theme_active_id
  end

  test "theme preference json includes skin fields" do
    get theme_url(format: :json)
    assert_response :success
    assert_equal "auto", response.parsed_body["active_skin_id"]
    assert_equal [], response.parsed_body["custom_skins"]
  end

  test "update persists active skin and custom skins" do
    patch theme_url(format: :json), params: {
      active_skin_id: "custom-skin-x",
      custom_skins: [
        { id: "custom-skin-x", label: "X", css: ".memo-body { color: teal }" }
      ]
    }, as: :json

    assert_response :no_content
    account = accounts(:one).reload
    assert_equal "custom-skin-x", account.theme_active_skin_id
    assert_equal 1, account.theme_preference_payload["custom_skins"].size
    assert_includes account.theme_preference_payload["custom_skins"].first["css"], "teal"
  end

  test "update persists builtin skin selection" do
    patch theme_url(format: :json), params: {
      active_skin_id: "github",
      custom_skins: []
    }, as: :json

    assert_response :no_content
    assert_equal "github", accounts(:one).reload.theme_active_skin_id
  end

  test "layout includes theme sync meta for signed-in user" do
    get memos_url
    assert_includes response.body, 'name="kbmemo-theme-sync"'
    assert_includes response.body, 'id="kbmemo-account-theme-json"'
    assert_includes response.body, '"active_theme_id":"default"'
    assert_select "head style#kbmemo-critical-icon-layout[nonce]", text: /data-lucide/
  end

  test "layout renders initial account theme before javascript runs" do
    account = Account.find(accounts(:one).id)
    account.update_theme_preference!(
      active_theme_id: "dark",
      active_skin_id: "github",
      custom_themes: [],
      custom_skins: []
    )
    sign_out
    sign_in_as(:one)

    get memos_url

    assert_response :success
    assert_select 'html[data-kb-theme="dark"][data-kb-theme-base="dark"][data-kb-skin="github"]'
    assert_select 'meta[name="color-scheme"][content="dark"]'
  end

  test "layout resolves custom theme base for initial render" do
    account = Account.find(accounts(:one).id)
    account.update_theme_preference!(
      active_theme_id: "custom-sepia",
      active_skin_id: "auto",
      custom_themes: [
        {
          id: "custom-sepia",
          label: "Custom Sepia",
          base_theme: "sepia",
          variables: { "--kb-bg-page" => "#f5ead2" },
          rules: []
        }
      ],
      custom_skins: []
    )
    sign_out
    sign_in_as(:one)

    get memos_url

    assert_response :success
    assert_select 'html[data-kb-theme="custom-sepia"][data-kb-theme-base="sepia"][data-kb-skin="auto"]'
    assert_select 'meta[name="color-scheme"][content="light"]'
  end
end
