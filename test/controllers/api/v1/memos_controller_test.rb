# frozen_string_literal: true

require "test_helper"

class Api::V1::MemosControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    @account = accounts(:one)
    @token = @account.generate_clip_api_token!
    @memo = memos(:one)
  end

  test "index returns authorized memos" do
    get api_v1_memos_path, headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    ids = body.fetch("memos").map { |row| row["id"] }
    assert_includes ids, @memo.id
    assert body.dig("pagination", "has_more").in?([ true, false ])
  end

  test "index filters by query" do
    get api_v1_memos_path, params: { q: "First" }, headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ @memo.id ], body.fetch("memos").map { |row| row["id"] }
  end

  test "index excludes drafts by default and includes them when requested" do
    draft = Memo.create!(
      account: @account,
      memo_directory: @memo.memo_directory,
      title: "Draft API memo",
      body: "= Draft",
      file_committed_at: nil
    )

    get api_v1_memos_path, headers: auth_headers

    assert_response :success
    ids = JSON.parse(response.body).fetch("memos").map { |row| row["id"] }
    assert_not_includes ids, draft.id

    get api_v1_memos_path, params: { include_drafts: true }, headers: auth_headers

    assert_response :success
    ids = JSON.parse(response.body).fetch("memos").map { |row| row["id"] }
    assert_includes ids, draft.id
  end

  test "index only returns group memos visible to token account" do
    visible = Memo.create!(
      account: accounts(:one),
      memo_directory: memo_directories(:work),
      title: "Alpha shared API memo",
      body: "= Alpha shared",
      visibility: :group_read,
      memo_group: memo_groups(:alpha),
      file_committed_at: Time.current
    )
    hidden = Memo.create!(
      account: accounts(:two),
      memo_directory: memo_directories(:home_u_two),
      title: "Beta private API memo",
      body: "= Beta shared",
      visibility: :group_read,
      memo_group: memo_groups(:beta),
      file_committed_at: Time.current
    )
    token = accounts(:two).generate_clip_api_token!

    get api_v1_memos_path, headers: auth_headers(token: token)

    assert_response :success
    ids = JSON.parse(response.body).fetch("memos").map { |row| row["id"] }
    assert_includes ids, visible.id
    assert_includes ids, hidden.id

    get api_v1_memos_path, headers: auth_headers

    assert_response :success
    ids = JSON.parse(response.body).fetch("memos").map { |row| row["id"] }
    assert_includes ids, visible.id
    assert_not_includes ids, hidden.id
  end

  test "show returns memo by uid" do
    get api_v1_memo_path(@memo.uid), headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @memo.uid, body["uid"]
    assert_equal "asciidoc", body["body_format"]
    assert_equal false, body["draft"]
  end

  test "show returns memo by numeric id" do
    get api_v1_memo_path(@memo.id), headers: auth_headers

    assert_response :success
    assert_equal @memo.id, JSON.parse(response.body)["id"]
  end

  test "show returns not found for missing memo" do
    get api_v1_memo_path("01J8X2K3M4N5P6Q7R8S9T0UVWX"), headers: auth_headers

    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body).dig("error", "code")
  end

  test "create memo commits to git by default" do
    assert_difference -> { @account.memos.count }, 1 do
      post api_v1_memos_path,
        params: { title: "API memo", body: "== Section\n\nHello from API." },
        headers: auth_headers,
        as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    memo = Memo.find(body.fetch("id"))
    assert_equal "API memo", memo.title
    assert memo.file_committed_at.present?
    assert_equal false, body["draft"]
  end

  test "create memo records view history so sidebar history lists it first" do
    assert_difference -> { MemoViewHistory.where(account_id: @account.id).count }, 1 do
      post api_v1_memos_path,
        params: { title: "History memo", body: "== Section\n\nVia API." },
        headers: auth_headers,
        as: :json
    end

    assert_response :created
    memo = Memo.find(JSON.parse(response.body).fetch("id"))
    recent = MemoViewHistory.recent_memos_for(@account, scope: Memo.where(account_id: @account.id))
    assert_equal memo.id, recent.first.id
  end

  test "create memo converts markdown body to asciidoc" do
    converted = "== Section\n\nHello from Markdown."

    with_markdown_converter(converted) do
      assert_difference -> { @account.memos.count }, 1 do
        post api_v1_memos_path,
          params: {
            title: "Markdown memo",
            body: "## Section\n\nHello from Markdown.",
            body_format: "markdown"
          },
          headers: auth_headers,
          as: :json
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    memo = Memo.find(body.fetch("id"))
    assert_equal converted, memo.body
    assert_equal "asciidoc", body["body_format"]
  end

  test "patch memo converts markdown append_body" do
    converted = "== Added\n\nMore text."
    updated_at = @memo.updated_at.utc.iso8601

    with_markdown_converter(converted) do
      patch api_v1_memo_path(@memo.uid),
        params: {
          updated_at: updated_at,
          append_body: "## Added\n\nMore text.",
          body_format: "markdown"
        },
        headers: auth_headers,
        as: :json
    end

    assert_response :success
    assert_includes JSON.parse(response.body)["body"], "== Added"
  end

  test "create memo without body returns validation error" do
    post api_v1_memos_path, params: { title: "No body" }, headers: auth_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_error", JSON.parse(response.body).dig("error", "code")
  end

  test "patch memo updates with optimistic lock" do
    updated_at = @memo.updated_at.utc.iso8601

    patch api_v1_memo_path(@memo.uid),
      params: { updated_at: updated_at, append_body: "追記本文" },
      headers: auth_headers,
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_includes body["body"], "追記本文"
  end

  test "patch memo with stale updated_at returns conflict" do
    stale = (@memo.updated_at - 1.hour).utc.iso8601

    patch api_v1_memo_path(@memo.uid),
      params: { updated_at: stale, body: "stale update" },
      headers: auth_headers,
      as: :json

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "stale_memo", body.dig("error", "code")
    assert_equal @memo.uid, body.dig("error", "current", "uid")
  end

  test "destroy memo returns no content" do
    delete api_v1_memo_path(@memo.uid), headers: auth_headers

    assert_response :no_content
    assert_not Memo.exists?(@memo.id)
  end

  test "unauthorized request returns structured error" do
    get api_v1_memos_path, headers: { "Accept" => "application/json" }

    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body).dig("error", "code")
  end

  private

  def auth_headers(token: @token)
    {
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json",
      "Content-Type" => "application/json"
    }
  end

  def with_markdown_converter(result)
    singleton = PandocMarkdownToAsciidoc.singleton_class
    original = PandocMarkdownToAsciidoc.method(:convert)
    singleton.define_method(:convert) { |_markdown| result }
    yield
  ensure
    singleton.define_method(:convert, original)
  end
end
