# frozen_string_literal: true

require "test_helper"

class MemoBodyReferencesTest < ActiveSupport::TestCase
  test "detects diagram and image macros outside fences" do
    body = <<~ADOC
      diagram::flow.mmd[]

      image::box.png[]

      ```
      diagram::ignored.mmd[]
      ```
    ADOC

    refs = MemoBodyReferences.new(body)
    assert refs.diagram_key?("flow.mmd")
    assert refs.asset_path?("box.png")
    assert_not refs.diagram_key?("ignored.mmd")
  end

  test "treats memo asset URL in image macro as relative path" do
    refs = MemoBodyReferences.new("image::/memos/14/assets/box.png[]")
    assert refs.asset_path?("box.png")
  end

  test "normalize_image_macro_paths rewrites absolute asset URLs" do
    body = "image::/memos/14/assets/box.png[]"
    assert_equal "image::box.png[]", MemoBodyReferences.normalize_image_macro_paths(body)
  end

  test "normalize_asset_path strips repeated memo asset prefixes" do
    path = "/memos/14/assets//memos/14/assets/box.png"
    assert_equal "box.png", MemoBodyReferences.normalize_asset_path(path)
  end
end
