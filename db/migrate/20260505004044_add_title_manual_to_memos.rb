class AddTitleManualToMemos < ActiveRecord::Migration[8.1]
  def change
    add_column :memos, :title_manual, :boolean, default: false, null: false
  end
end
