# frozen_string_literal: true

require "test_helper"

class AccountThemePreferenceTest < ActiveSupport::TestCase
  test "normalize_theme_preference defaults to empty builtin theme" do
    payload = Account.normalize_theme_preference({})

    assert_equal "default", payload["active_theme_id"]
    assert_equal [], payload["custom_themes"]
  end

  test "normalize_theme_preference keeps custom themes" do
    payload = Account.normalize_theme_preference(
      "active_theme_id" => "custom-abc",
      "custom_themes" => [
        {
          "id" => "custom-abc",
          "label" => "Mine",
          "base_theme" => "dark",
          "variables" => { "--kb-bg-page" => "#000000" },
          "rules" => [{ "selector" => "[data-theme-slot=\"memo-body\"]", "properties" => { "color" => "#fff" } }]
        }
      ]
    )

    assert_equal "custom-abc", payload["active_theme_id"]
    assert_equal 1, payload["custom_themes"].size
    assert_equal "dark", payload["custom_themes"].first["base_theme"]
    assert_equal "#000000", payload["custom_themes"].first["variables"]["--kb-bg-page"]
  end

  test "account update_theme_preference persists normalized payload" do
    account = accounts(:one)
    account.update_theme_preference!(
      active_theme_id: "dark",
      custom_themes: []
    )

    account.reload
    assert_equal "dark", account.theme_active_id
    assert_equal "dark", account.theme_preference_payload["active_theme_id"]
  end

  test "normalize_theme_preference defaults skin to auto" do
    payload = Account.normalize_theme_preference({})

    assert_equal "auto", payload["active_skin_id"]
    assert_equal [], payload["custom_skins"]
  end

  test "normalize_theme_preference keeps custom skins and strips @import" do
    payload = Account.normalize_theme_preference(
      "active_skin_id" => "custom-skin-1",
      "custom_skins" => [
        {
          "id" => "custom-skin-1",
          "label" => "Mine",
          "css" => "@import url(http://evil/x.css); .memo-body { color: red }"
        }
      ]
    )

    assert_equal "custom-skin-1", payload["active_skin_id"]
    assert_equal 1, payload["custom_skins"].size
    refute_includes payload["custom_skins"].first["css"], "@import"
    assert_includes payload["custom_skins"].first["css"], ".memo-body"
  end

  test "theme_active_skin_id falls back to auto for an unknown skin id" do
    account = accounts(:one)
    account.update_theme_preference!(active_skin_id: "nope", custom_skins: [])

    assert_equal "auto", account.reload.theme_active_skin_id
  end

  test "account persists builtin skin selection" do
    account = accounts(:one)
    account.update_theme_preference!(active_skin_id: "github", custom_skins: [])

    assert_equal "github", account.reload.theme_active_skin_id
  end
end
