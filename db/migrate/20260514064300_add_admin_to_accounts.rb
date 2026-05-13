# frozen_string_literal: true

class AddAdminToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :admin, :boolean, null: false, default: false
  end
end
