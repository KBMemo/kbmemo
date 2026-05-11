class CreateMemos < ActiveRecord::Migration[8.1]
  def change
    create_table :memos do |t|
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.json :properties, null: false, default: {}
      t.string :slug

      t.timestamps
    end

    add_index :memos, :slug, unique: true
  end
end
