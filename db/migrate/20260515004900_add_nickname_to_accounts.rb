# frozen_string_literal: true

class AddNicknameToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :nickname, :string
  end
end
