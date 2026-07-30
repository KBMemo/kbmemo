# frozen_string_literal: true

require "test_helper"

class Api::ClipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    @account = accounts(:one)
    _record, @token = WebClipToken.issue!(account: @account, name: "Test browser")
  end

  test "create clip with bearer token saves memo under clippings directory" do
    html = <<~HTML
      <!--kbmemo:{"url":"https://example.com/article","title":"Article Title"}-->
      <blockquote cite="https://example.com/article"><p><strong>Clip</strong> body</p></blockquote>
    HTML

    assert_difference -> { @account.memos.count }, 1 do
      post api_clips_path,
        params: {
          html: html,
          url: "https://example.com/article",
          title: "Article Title",
          mode: "selection"
        },
        headers: auth_headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    memo = Memo.find(body.fetch("id"))

    assert_equal "home/u-#{@account.id}/clippings", memo.memo_directory.full_path
    assert_equal "Article Title", memo.title
    assert_includes memo.tags.pluck(:name), "web-clip"
    assert_equal "https://example.com/article", memo.properties["source_url"]
    assert_equal "selection", memo.properties["clip_mode"]
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

  test "article mode extracts page content before saving" do
    html = <<~HTML
      <html><body>
        <nav>Global navigation</nav>
        <article><h1>Full article</h1><p>Article body text.</p></article>
        <footer>Footer links</footer>
      </body></html>
    HTML

    post api_clips_path,
      params: { html: html, mode: "article", title: "Full article", url: "https://example.com/full" },
      headers: auth_headers

    assert_response :created
    memo = Memo.find(JSON.parse(response.body).fetch("id"))
    assert_includes memo.body, "Article body text"
    assert_not_includes memo.body, "Global navigation"
    assert_not_includes memo.body, "Footer links"
    assert_equal "article", memo.properties["clip_mode"]
  end

  test "summary mode saves generated summary" do
    ClipSummarizer.stub(:call, "要約本文\n\n== 重要ポイント\n\n* 要点") do
      post api_clips_path,
        params: {
          html: "<html><body><main><p>Long article body.</p></main></body></html>",
          mode: "summary",
          title: "Summary article"
        },
        headers: auth_headers
    end

    assert_response :created
    memo = Memo.find(JSON.parse(response.body).fetch("id"))
    assert_includes memo.body, "要約本文"
    assert_equal "summary", memo.properties["clip_mode"]
  end

  test "summary failure does not leave an empty memo" do
    before_count = @account.memos.count

    ClipSummarizer.stub(:call, ->(**) { raise ClipSummarizer::Error, "model unavailable" }) do
      post api_clips_path,
        params: {
          html: "<html><body><main><p>Long article body.</p></main></body></html>",
          mode: "summary",
          title: "Failed summary"
        },
        headers: auth_headers
    end

    assert_response :unprocessable_entity
    assert_equal before_count, @account.memos.count
  end

  test "rejects an oversized page" do
    post api_clips_path,
      params: { html: "x" * (Api::ClipsController::MAX_HTML_BYTES + 1), mode: "article" },
      headers: auth_headers,
      as: :json

    assert_response :content_too_large
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
