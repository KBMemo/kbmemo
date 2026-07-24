# frozen_string_literal: true

require "test_helper"

class MemoTemplatesControllerTest < ActionDispatch::IntegrationTest
  test "index lists only the signed-in account templates" do
    get memo_templates_url

    assert_response :success
    assert_includes response.body, memo_templates(:daily).name
    assert_not_includes response.body, memo_templates(:other).name
  end

  test "creates a template" do
    assert_difference("accounts(:one).memo_templates.count", 1) do
      post memo_templates_url, params: {
        memo_template: {
          name: "Meeting",
          title_template: "Meeting {{created_on}}",
          body_template: "== Agenda",
          tag_list: "meeting"
        }
      }
    end

    assert_redirected_to memo_templates_url
  end

  test "updates an owned template" do
    patch memo_template_url(memo_templates(:daily)), params: {
      memo_template: { name: "Updated daily" }
    }

    assert_redirected_to memo_templates_url
    assert_equal "Updated daily", memo_templates(:daily).reload.name
  end

  test "cannot edit another account template" do
    get edit_memo_template_url(memo_templates(:other))

    assert_response :not_found
  end

  test "destroys an owned template" do
    assert_difference("MemoTemplate.count", -1) do
      delete memo_template_url(memo_templates(:daily))
    end

    assert_redirected_to memo_templates_url
  end
end
