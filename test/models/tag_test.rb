# == Schema Information
#
# Table name: tags
#
#  id              :integer          not null, primary key
#  name            :string           not null
#  normalized_name :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_tags_on_normalized_name  (normalized_name) UNIQUE
#
require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "merge_into moves memos to target and destroys source" do
    source = tags(:one)
    target = tags(:two)
    memo = memos(:one)

    assert_includes memo.tags, source
    assert_not_includes memo.tags, target

    source.merge_into!(target)

    assert_not Tag.exists?(source.id)
    memo.reload
    assert_includes memo.tags, target
  end

  test "merge_into removes duplicate link when memo already has target" do
    source = tags(:one)
    target = tags(:two)
    memo = memos(:one)
    memo.memo_tags.create!(tag: target)

    source.merge_into!(target)

    assert_not Tag.exists?(source.id)
    memo.reload
    assert_equal 1, memo.memo_tags.where(tag_id: target.id).count
  end

  test "merge_into raises when merging into self" do
    tag = tags(:one)
    assert_raises(ArgumentError) { tag.merge_into!(tag) }
  end
end
