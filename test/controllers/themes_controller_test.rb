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
    assert_includes response.body, "data-controller=\"theme-studio\""
  end
end
