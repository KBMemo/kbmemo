# frozen_string_literal: true

require "test_helper"

class MemoTemplateRendererTest < ActiveSupport::TestCase
  test "expands the creation date macro in every template field" do
    result = MemoTemplateRenderer.new(
      template: memo_templates(:daily),
      created_on: Date.new(2026, 7, 24)
    ).call

    assert_equal "Daily 2026-07-24", result.title
    assert_includes result.body, "= Daily 2026-07-24"
    assert_equal "diary, 2026-07-24", result.tag_list
  end

  test "leaves unknown macros unchanged" do
    template = MemoTemplate.new(
      title_template: "{{unknown}}",
      body_template: "",
      tag_list: ""
    )

    assert_equal "{{unknown}}", MemoTemplateRenderer.new(template: template).call.title
  end
end
