# frozen_string_literal: true

class ChangeMemosPropertiesToJsonb < ActiveRecord::Migration[8.1]
  def up
    change_column :memos, :properties, :jsonb, default: {}, null: false, using: "properties::jsonb"
  end

  def down
    change_column :memos, :properties, :json, default: {}, null: false, using: "properties::json"
  end
end
