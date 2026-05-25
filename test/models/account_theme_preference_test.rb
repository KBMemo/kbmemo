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
end
