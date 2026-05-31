# == Schema Information
#
# Table name: memo_tags
#
#  id      :bigint           not null, primary key
#  memo_id :integer          not null
#  tag_id  :integer          not null
#
# Indexes
#
#  index_memo_tags_on_memo_id             (memo_id)
#  index_memo_tags_on_memo_id_and_tag_id  (memo_id,tag_id) UNIQUE
#  index_memo_tags_on_tag_id              (tag_id)
#
# Foreign Keys
#
#  fk_rails_...  (memo_id => memos.id)
#  fk_rails_...  (tag_id => tags.id)
#
require "test_helper"

class MemoTagTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
