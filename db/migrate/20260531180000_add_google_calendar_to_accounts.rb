# frozen_string_literal: true

class AddGoogleCalendarToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :google_calendar_refresh_token, :text
    add_column :accounts, :google_calendar_meta, :json, null: false, default: {}
  end
end
