# frozen_string_literal: true

class AddChatServerSettingsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :chat_server_settings, :jsonb, null: false, default: {}
  end
end
