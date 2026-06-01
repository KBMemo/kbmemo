# frozen_string_literal: true

class AddTsuzuraApiTokenToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :tsuzura_api_token_digest, :string
    add_column :accounts, :tsuzura_api_token_prefix, :string
    add_column :accounts, :tsuzura_api_token_created_at, :datetime
    add_index :accounts, :tsuzura_api_token_digest, unique: true
  end
end
