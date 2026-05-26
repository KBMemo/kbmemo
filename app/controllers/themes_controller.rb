# frozen_string_literal: true

class ThemesController < ApplicationController
  def studio
    @editing_theme_id = params[:theme].presence
  end

  def show
    render json: theme_json_payload
  end

  def update
    current_account.update_theme_preference!(theme_params.to_h)
    head :no_content
  end

  private

  def current_account
    rodauth.rails_account
  end

  def theme_json_payload
    payload = current_account.theme_preference_payload
    {
      active_theme_id: payload["active_theme_id"],
      custom_themes: payload["custom_themes"].map { |theme| camelize_custom_theme(theme) }
    }
  end

  def theme_params
    payload = request.request_parameters
    source = payload["theme"].is_a?(Hash) ? payload["theme"] : payload

    ActionController::Parameters.new(source).permit(
      :active_theme_id,
      custom_themes: [
        :id,
        :label,
        :base_theme,
        { variables: {} },
        { rules: [:selector, { properties: {} }] }
      ]
    )
  end

  def camelize_custom_theme(theme)
    {
      id: theme["id"],
      label: theme["label"],
      baseTheme: theme["base_theme"],
      variables: theme["variables"] || {},
      rules: Array(theme["rules"]).map do |rule|
        {
          selector: rule["selector"],
          properties: rule["properties"] || {}
        }
      end
    }
  end
end
