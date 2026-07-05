# frozen_string_literal: true

class RemoveMemoDirectoryFromNotebooks < ActiveRecord::Migration[8.0]
  def change
    remove_reference :notebooks, :memo_directory, foreign_key: true
  end
end
