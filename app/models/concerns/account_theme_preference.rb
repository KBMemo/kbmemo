# frozen_string_literal: true

module AccountThemePreference
  extend ActiveSupport::Concern

  BUILTIN_THEME_IDS = %w[default dark sepia minimal].freeze
  THEME_PREFERENCE_VERSION = 1

  class_methods do
    def normalize_theme_preference(raw)
      data = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      active = data["active_theme_id"].presence || data["activeThemeId"].presence || "default"
      active = BUILTIN_THEME_IDS.include?(active) ? active : active.to_s

      custom_themes = Array(data["custom_themes"] || data["customThemes"]).filter_map do |entry|
        normalize_custom_theme(entry)
      end

      {
        "active_theme_id" => active,
        "custom_themes" => custom_themes
      }
    end

    def normalize_custom_theme(raw)
      return nil unless raw.is_a?(Hash)

      data = raw.deep_stringify_keys
      id = data["id"].presence
      label = data["label"].presence
      base_theme = data["base_theme"].presence || data["baseTheme"].presence || "default"
      base_theme = BUILTIN_THEME_IDS.include?(base_theme) ? base_theme : "default"
      return nil if id.blank? || label.blank?

      variables = normalize_string_hash(data["variables"])
      rules = Array(data["rules"]).filter_map { |rule| normalize_theme_rule(rule) }

      {
        "id" => id,
        "label" => label,
        "base_theme" => base_theme,
        "variables" => variables,
        "rules" => rules
      }
    end

    def normalize_string_hash(raw)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(key, value), acc|
        next unless key.is_a?(String) || key.is_a?(Symbol)
        next unless value.is_a?(String)

        acc[key.to_s] = value
      end
    end

    def normalize_theme_rule(raw)
      return nil unless raw.is_a?(Hash)

      data = raw.deep_stringify_keys
      selector = data["selector"].presence
      properties = normalize_string_hash(data["properties"])
      return nil if selector.blank? || properties.empty?

      { "selector" => selector, "properties" => properties }
    end
  end

  def theme_preference_payload
    self.class.normalize_theme_preference(theme_preference)
  end

  def theme_active_id
    active = theme_preference_payload["active_theme_id"]
    custom_ids = theme_preference_payload["custom_themes"].map { |theme| theme["id"] }
    return active if BUILTIN_THEME_IDS.include?(active) || custom_ids.include?(active)

    "default"
  end

  def update_theme_preference!(payload)
    update!(theme_preference: self.class.normalize_theme_preference(payload))
  end
end
