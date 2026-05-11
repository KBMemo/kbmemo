require "test_helper"

class MemosControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get memos_url
    assert_response :success
  end

  test "edit has memo draft stimulus bindings" do
    get edit_memo_url(memos(:one))
    assert_response :success
    assert_includes response.body, 'data-controller="memo-draft"'
    assert_includes response.body, 'data-action="submit-&gt;memo-draft#preventSubmit"'
  end

  test "should create memo and redirect" do
    assert_difference("Memo.count", 1) do
      post memos_url, params: {
        memo: {
          title: "Ui smoke",
          body: "= Doc\n\nHello.",
          slug: "",
          tag_list: "alpha, beta",
          properties_json: "{\n  \"priority\": 1\n}"
        }
      }
    end
    assert_redirected_to edit_memo_url(Memo.last)
    follow_redirect!
    assert_response :success
    assert_match(/Ui smoke/, response.body)
  end

  test "draft saves all fields without validations" do
    memo = memos(:one)
    patch draft_memo_url(memo),
      params: {
        memo: {
          body: "= Draft title\n\nBody.",
          title_manual: false,
          slug: "draft-slug",
          tag_list: "draft-tag, other",
          properties_json: '{"k":1}'
        }
      },
      as: :json
    assert_response :success
    memo.reload
    assert_equal "= Draft title\n\nBody.", memo.body
    assert_equal "Draft title", memo.title
    assert_equal "draft-slug", memo.slug
    assert_equal({ "k" => 1 }, memo.properties)
    assert_includes memo.tags.map(&:name), "draft-tag"
    assert_not memo.title_manual
    body = JSON.parse(response.body)
    assert_equal memo.title, body["title"]
  end

  test "body draft save works even when properties field is currently invalid on client" do
    memo = memos(:one)
    # properties_json は送らない（別フィールド単位保存）
    patch draft_memo_url(memo),
      params: { memo: { body: "= Updated only body\n\nText" } },
      as: :json
    assert_response :success
    memo.reload
    assert_equal "= Updated only body\n\nText", memo.body
    assert_equal "Updated only body", memo.title
  end

  test "draft can respond with turbo stream for title sync" do
    memo = memos(:one)
    patch draft_memo_url(memo),
      params: { memo: { body: "= Stream title\n\nBody" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.media_type, "vnd.turbo-stream.html"
    assert_includes response.body, "memo_title_field"
  end

  test "draft broadcasts show content replace to memo turbo stream" do
    memo = memos(:one)
    assert_turbo_stream_broadcasts memo do
      patch draft_memo_url(memo),
        params: { memo: { body: "= Broadcast title\n\nBody text." } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
    end
  end

  test "create via json returns edit path for autosave bootstrap" do
    assert_difference("Memo.count", 1) do
      post memos_url,
        params: {
          memo: {
            body: "= From Json\n",
            title_manual: false,
            slug: "",
            tag_list: "json-tag",
            properties_json: "{}"
          }
        },
        as: :json
    end
    assert_response :created
    json = JSON.parse(response.body)
    assert json["edit_path"].present?
    assert json["draft_url"].present?
    m = Memo.order(:id).last
    assert_equal "From Json", m.title
    assert_includes m.tags.map(&:name), "json-tag"
  end

  test "should reject invalid properties json" do
    assert_no_difference("Memo.count") do
      post memos_url, params: {
        memo: {
          title: "Bad json",
          body: "",
          properties_json: "{"
        }
      }
    end
    assert_response :unprocessable_entity
  end
end
