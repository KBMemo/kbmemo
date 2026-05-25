# frozen_string_literal: true

class AddThemePreferenceToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :theme_preference, :json, default: {}, null: false
  end
end
