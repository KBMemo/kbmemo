# frozen_string_literal: true

require "test_helper"

class AppImagesControllerTest < ActionDispatch::IntegrationTest
  test "show redirects to propshaft asset url" do
    get app_image_path("octocat.jpg")

    assert_response :redirect
    assert_match %r{/assets/octocat-[0-9a-f]+\.jpg\z}, response.location
  end

  test "show returns not found for missing asset" do
    get app_image_path("missing-file.png")

    assert_response :not_found
  end

  test "show does not require authentication" do
    get app_image_path("octocat.jpg")

    assert_response :redirect
  end
end
