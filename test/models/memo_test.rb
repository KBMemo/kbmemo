# == Schema Information
#
# Table name: memos
#
#  id           :integer          not null, primary key
#  body         :text             default(""), not null
#  properties   :json             not null
#  slug         :string
#  title        :string           not null
#  title_manual :boolean          default(FALSE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_memos_on_slug  (slug) UNIQUE
#
require "test_helper"

class MemoTest < ActiveSupport::TestCase
  test "derived_title_from_body strips leading equals and uses first line" do
    assert_equal "Hello", Memo.derived_title_from_body("= Hello\n\nMore")
    assert_equal "Hello", Memo.derived_title_from_body("=== Hello")
    assert_equal "Plain", Memo.derived_title_from_body("Plain\nother")
    assert_equal Memo::TITLE_PLACEHOLDER, Memo.derived_title_from_body("")
    assert_equal Memo::TITLE_PLACEHOLDER, Memo.derived_title_from_body("\n\n")
  end

  test "title stays manual when user sets title different from derived" do
    m = Memo.new(body: "Line1\nLine2", title: "Custom", title_manual: false)
    m.valid?
    assert m.title_manual?
    assert_equal "Custom", m.title
  end

  test "title syncs from body when not manual" do
    m = Memo.new(body: "= Doc title\n\nx", title_manual: false)
    m.valid?
    assert_not m.title_manual?
    assert_equal "Doc title", m.title
  end

  test "placeholder title is treated as unfilled" do
    m = Memo.new(body: "", title: Memo::TITLE_PLACEHOLDER, title_manual: true)
    m.valid?
    assert m.title_unfilled?
    assert_equal Memo::TITLE_PLACEHOLDER, m.title
  end
end
