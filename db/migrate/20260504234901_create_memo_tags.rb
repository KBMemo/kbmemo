class CreateMemoTags < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_tags do |t|
      t.references :memo, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
    end

    add_index :memo_tags, %i[memo_id tag_id], unique: true
  end
end
