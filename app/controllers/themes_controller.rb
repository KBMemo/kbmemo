# frozen_string_literal: true

class ThemesController < ApplicationController
  def studio
    @editing_theme_id = params[:theme].presence
  end
end
