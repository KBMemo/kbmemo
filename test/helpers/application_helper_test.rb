# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "kb_field_error_aria links invalid fields to error and help text" do
    tag = Tag.new(name: "")
    tag.errors.add(:name, "を入力してください")

    assert_equal(
      { invalid: true, describedby: "tag-name-help tag_name_error" },
      kb_field_error_aria(tag, :name, describedby: "tag-name-help")
    )
  end

  test "kb_field_error_aria returns nil without field errors" do
    tag = Tag.new(name: "Ideas")

    assert_nil kb_field_error_aria(tag, :name, describedby: "tag-name-help")
  end
end
