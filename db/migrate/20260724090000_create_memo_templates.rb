# frozen_string_literal: true

class CreateMemoTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :title_template, null: false, default: ""
      t.text :body_template, null: false, default: ""
      t.text :tag_list, null: false, default: ""

      t.timestamps
    end

    add_index :memo_templates, %i[account_id name], unique: true
  end
end
