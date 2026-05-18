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
end
