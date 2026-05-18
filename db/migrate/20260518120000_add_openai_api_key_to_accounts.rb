# frozen_string_literal: true

class AddOpenaiApiKeyToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :openai_api_key, :text
  end
end
