# frozen_string_literal: true

class MakeMemoSlugGloballyUnique < ActiveRecord::Migration[8.1]
  def up
    Memo.reset_column_information
    Memo.find_each do |memo|
      next if memo.slug.blank?

      stem = Memo.slug_stem(memo.slug, memo_id: memo.id)
      new_slug = Memo.global_slug_for(stem, memo.id)
      memo.update_column(:slug, new_slug) if memo.slug != new_slug
    end

    remove_index :memos, %i[memo_directory_id slug]
    add_index :memos, :slug, unique: true
  end

  def down
    remove_index :memos, :slug
    add_index :memos, %i[memo_directory_id slug], unique: true
  end
end
