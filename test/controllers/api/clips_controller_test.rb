# frozen_string_literal: true

require "test_helper"

class Api::ClipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    @account = accounts(:one)
    @token = @account.generate_web_clip_token!
  end

  test "create clip with bearer token saves memo under clippings directory" do
    html = <<~HTML
      <!--kbmemo:{"url":"https://example.com/article","title":"Article Title"}-->
      <blockquote cite="https://example.com/article"><p><strong>Clip</strong> body</p></blockquote>
    HTML

    assert_difference -> { @account.memos.count }, 1 do
      post api_clips_path,
        params: { html: html, url: "https://example.com/article", title: "Article Title" },
        headers: auth_headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    memo = Memo.find(body.fetch("id"))

    assert_equal "home/u-#{@account.id}/clippings", memo.memo_directory.full_path
    assert_equal "Article Title", memo.title
    assert_equal "https://example.com/article", memo.properties["source_url"]
    assert_includes memo.body, "*Clip*"
    assert_not_includes memo.body, "____"
    assert_not_includes memo.body, "<blockquote"
    assert_includes memo.body, "link:https://example.com/article"
    assert_equal edit_memo_path(memo), body["edit_path"]
  end

  test "create clip without token returns unauthorized" do
    post api_clips_path,
      params: { html: "<p>x</p>" },
      headers: { "Origin" => "https://www.kspub.co.jp" }

    assert_response :unauthorized
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
  end

  test "account api token can also create a clip" do
    @token = @account.generate_api_token!

    post api_clips_path, params: { plain: "clip body" }, headers: auth_headers

    assert_response :created
  end

  test "create clip without html or plain returns unprocessable entity" do
    post api_clips_path, params: { title: "Only title" }, headers: auth_headers

    assert_response :unprocessable_entity
  end

  test "options preflight returns no content without auth" do
    process :options, api_clips_path

    assert_response :no_content
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
  end

  private

  def auth_headers
    {
      "Authorization" => "Bearer #{@token}",
      "Accept" => "application/json"
    }
  end
end
