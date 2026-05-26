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

  test "layout includes theme sync meta for signed-in user" do
    get memos_url
    assert_includes response.body, 'name="kbmemo-theme-sync"'
    assert_includes response.body, "__KBMEMO_ACCOUNT_THEME__"
  end
end
