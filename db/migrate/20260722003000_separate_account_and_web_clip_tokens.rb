# frozen_string_literal: true

class SeparateAccountAndWebClipTokens < ActiveRecord::Migration[8.1]
  def change
    rename_column :accounts, :clip_api_token_digest, :api_token_digest
    rename_column :accounts, :clip_api_token_prefix, :api_token_prefix
    rename_column :accounts, :clip_api_token_created_at, :api_token_created_at
    add_column :accounts, :web_clip_token_digest, :string
    add_column :accounts, :web_clip_token_prefix, :string
    add_column :accounts, :web_clip_token_created_at, :datetime
    add_index :accounts, :web_clip_token_digest, unique: true
  end
end
