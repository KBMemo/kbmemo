# frozen_string_literal: true

class AddNyoyMcpSettingsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :nyoy_mcp_url, :string
    add_column :accounts, :nyoy_mcp_api_token, :text
  end
end
