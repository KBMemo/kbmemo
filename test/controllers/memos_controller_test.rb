require "test_helper"

class MemosControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get memos_url
    assert_response :success
  end

  test "tag sidebar redirects to first tag when tag_id omitted" do
    first = Tag.order(:name).first
    assert first

    get memos_url(sidebar_view: "tag")
    assert_redirected_to memos_url(sidebar_view: "tag", tag_id: first.id)
  end

  test "tag sidebar lists memos for selected tag" do
    tag = tags(:two)
    get memos_url(sidebar_view: "tag", tag_id: tag.id)
    assert_response :success
    assert_includes response.body, tag.name
    assert_includes response.body, memos(:two).title
    assert_not_includes response.body, memos(:one).title
  end

  test "memo list row links to edit when draft and to show when file committed" do
    draft = memos(:one)
    committed = memos(:two)
    t = 1.hour.ago.change(usec: 0)
    committed.update_columns(file_committed_at: t, updated_at: t, memo_directory_id: draft.memo_directory_id)

    dir = draft.memo_directory
    get memos_url(memo_directory_id: dir.id)
    assert_response :success
    assert_includes response.body, edit_memo_path(draft)
    assert_includes response.body, memo_path(committed)
  end

  test "memo list uses edit link after committed memo is changed by draft" do
    committed = memos(:two)
    t = 1.hour.ago.change(usec: 0)
    committed.update_columns(file_committed_at: t, updated_at: t, memo_directory_id: memos(:one).memo_directory_id)

    patch draft_memo_url(committed), params: { memo: { body: "= Revised\n\nx" } }, as: :json
    assert_response :success
    assert committed.reload.display_as_draft?

    get memos_url(memo_directory_id: committed.memo_directory_id)
    assert_includes response.body, edit_memo_path(committed)
  end

  test "draft can change memo directory" do
    m = memos(:one)
    work = memo_directories(:work)
    patch draft_memo_url(m), params: { memo: { memo_directory_id: work.id } }, as: :json
    assert_response :success
    assert_equal work.id, m.reload.memo_directory_id
  end

  test "draft directory change turbo stream refreshes sidebar selection" do
    m = memos(:one)
    share_u1 = MemoDirectory.find_by!(full_path: "share/u-1")
    patch draft_memo_url(m),
      params: { memo: { memo_directory_id: share_u1.id } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, %(memo_directory_id=#{share_u1.id})
    assert_includes response.body, "bg-zinc-200 font-medium text-zinc-900"
  end

  test "draft rejects top level bucket as memo directory" do
    m = memos(:one)
    home = memo_directories(:home)
    patch draft_memo_url(m), params: { memo: { memo_directory_id: home.id } }, as: :json
    assert_response :unprocessable_entity
    assert_not_equal home.id, m.reload.memo_directory_id
  end

  test "edit has memo draft stimulus bindings" do
    get edit_memo_url(memos(:one))
    assert_response :success
    assert_includes response.body, 'data-controller="memo-draft"'
    assert_includes response.body, 'data-controller="memo-directory-dnd"'
    assert_includes response.body, "memo-draft#preventSubmit"
    assert_includes response.body, "memo-draft#suppressEnterSubmit"
    assert_includes response.body, "memo_slug_field"
  end

  test "should create memo and redirect" do
    assert_difference("Memo.count", 1) do
      post memos_url, params: {
        memo: {
          title: "Ui smoke",
          body: "= Doc\n\nHello.",
          slug: "",
          tag_list: "alpha, beta",
          properties_yaml: "priority: 1"
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
          properties_yaml: "k: 1"
        }
      },
      as: :json
    assert_response :success
    memo.reload
    assert_equal "= Draft title\n\nBody.", memo.body
    assert_equal "Draft title", memo.title
    assert_equal "draft-title", memo.slug
    assert_equal({ "k" => 1 }, memo.properties)
    assert_includes memo.tags.map(&:name), "draft-tag"
    assert_not memo.title_manual
    body = JSON.parse(response.body)
    assert_equal memo.title, body["title"]
  end

  test "body draft save works even when properties field is currently invalid on client" do
    memo = memos(:one)
    # properties_yaml は送らない（別フィールド単位保存）
    patch draft_memo_url(memo),
      params: { memo: { body: "= Updated only body\n\nText" } },
      as: :json
    assert_response :success
    memo.reload
    assert_equal "= Updated only body\n\nText", memo.body
    assert_equal "Updated only body", memo.title
  end

  test "update writes memo file and commits to git" do
    memo = memos(:one)
    patch memo_url(memo),
      params: {
        memo: {
          title: "Git integration title",
          body: "= Git integration\n\nParagraph.",
          slug: "git-integration-slug",
          title_manual: "1"
        }
      }
    assert_redirected_to memo_path(memo)
    memo.reload
    assert memo.file_committed_at.present?
    assert_equal memo.updated_at.to_i, memo.file_committed_at.to_i
    repo = MemoRepository.new
    assert_predicate repo.absolute_path_for(memo), :exist?
    assert_includes repo.absolute_path_for(memo).read, "Git integration"
  end

  test "draft can respond with turbo stream for title sync" do
    memo = memos(:one)
    patch draft_memo_url(memo),
      params: { memo: { body: "= Stream title\n\nBody" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.media_type, "vnd.turbo-stream.html"
    assert_includes response.body, "memo_title_field"
    assert_includes response.body, "memo_slug_field"
    assert_includes response.body, "memo_directory_field"
  end

  test "draft turbo stream keeps memos_list_panel id so repeated saves refresh sidebar" do
    memo = memos(:one)
    headers = { "Accept" => "text/vnd.turbo-stream.html" }
    patch draft_memo_url(memo), params: { memo: { body: "= First sidebar title\n\nA." } }, headers: headers
    assert_response :success
    assert_includes response.body, 'id="memos_list_panel"'

    patch draft_memo_url(memo), params: { memo: { body: "= Second sidebar title\n\nB." } }, headers: headers
    assert_response :success
    assert_includes response.body, "Second sidebar title"
    assert_includes response.body, 'id="memos_list_panel"'
  end

  test "draft json returns normalized slug" do
    memo = memos(:one)
    patch draft_memo_url(memo),
      params: { memo: { slug: "  WEIRD SLUG!!  ", title: "Fixed", title_manual: true, slug_manual: true } },
      as: :json
    assert_response :success
    memo.reload
    assert_equal "weird-slug", memo.slug
    body = JSON.parse(response.body)
    assert_equal "weird-slug", body["slug"]
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
            properties_yaml: "{}"
          }
        },
        as: :json
    end
    assert_response :created
    json = JSON.parse(response.body)
    assert json["edit_path"].present?
    assert json["draft_url"].present?
    assert_equal "from-json", json["slug"]
    m = Memo.order(:id).last
    assert_equal "From Json", m.title
    assert_includes m.tags.map(&:name), "json-tag"
  end

  test "should reject invalid properties yaml" do
    assert_no_difference("Memo.count") do
      post memos_url, params: {
        memo: {
          title: "Bad yaml",
          body: "",
          properties_yaml: "[not a mapping"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "guest can show public memo without signing in" do
    memos(:one).update_columns(visibility: Memo.visibilities[:public_everyone])
    post "/logout"
    get memo_url(memos(:one))
    assert_response :success
  end

  test "guest gets not found for non-public memo" do
    post "/logout"
    memos(:one).update_columns(visibility: Memo.visibilities[:owner_read_write])
    get memo_url(memos(:one))
    assert_response :not_found
  end

  test "guest cannot access memo index" do
    post "/logout"
    get memos_url
    assert_response :redirect
  end
end
