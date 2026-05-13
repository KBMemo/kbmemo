# frozen_string_literal: true

require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  test "index lists tags with memo counts" do
    get tags_url
    assert_response :success
    assert_includes response.body, tags(:one).name
    assert_includes response.body, tags(:two).name
  end

  test "update renames tag" do
    tag = tags(:one)
    patch tag_url(tag), params: { tag: { name: "Ideas Renamed" } }
    assert_redirected_to tags_url
    assert_equal "Ideas Renamed", tag.reload.name
  end

  test "destroy removes unused tag" do
    orphan = Tag.create!(name: "UnusedOnly")
    assert_difference("Tag.count", -1) do
      delete tag_url(orphan)
    end
    assert_redirected_to tags_url
  end

  test "destroy rejects tag still used by memos" do
    tag = tags(:one)
    assert_no_difference("Tag.count") do
      delete tag_url(tag)
    end
    assert_redirected_to tags_url
    follow_redirect!
    assert_match(/紐付いている/, flash[:alert].to_s)
  end

  test "merge combines source into target" do
    source = tags(:one)
    target = tags(:two)
    post merge_tags_url, params: { source_tag_id: source.id, target_tag_id: target.id }
    assert_redirected_to tags_url
    assert_not Tag.exists?(source.id)
    assert memos(:one).reload.tags.include?(target)
  end

  test "merge rejects same source and target" do
    tag = tags(:one)
    post merge_tags_url, params: { source_tag_id: tag.id, target_tag_id: tag.id }
    assert_redirected_to merge_tags_url(from_tag_id: tag.id)
    follow_redirect!
    assert_match(/同じタグ/, flash[:alert].to_s)
  end

  test "merge form loads" do
    get merge_tags_url
    assert_response :success
  end
end
