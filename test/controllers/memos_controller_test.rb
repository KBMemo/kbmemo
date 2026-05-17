require "test_helper"

class MemosControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get memos_url
    assert_response :success
  end

  test "index search finds memos by title or body across directories" do
    m = memos(:one)
    m.update_columns(title: "UniqueSearchToken", body: "body")
    get memos_url(sidebar_view: "search", q: "UniqueSearchToken")
    assert_response :success
    assert_includes response.body, m.title
    assert_includes response.body, "検索結果"
  end

  test "index redirects legacy q param to search tab" do
    get memos_url(q: "hello")
    assert_redirected_to memos_url(sidebar_view: "search", q: "hello")
  end

  test "show from search directory tab stays on memo and syncs directory sidebar" do
    m = memos(:one)
    dir = m.memo_directory
    m.update_columns(title: "SidebarSyncSearch", body: "body")

    get edit_memo_url(m, sidebar_view: "search", q: "SidebarSyncSearch")
    assert_response :success
    assert_select "a", text: "ディレクトリ" do |links|
      href = links.first["href"]
      assert_includes href, "memo_directory_id=#{dir.id}"
      assert_not_includes href, "sidebar_view=search"
    end

    get edit_memo_url(m, memo_directory_id: dir.id)
    assert_response :success
    assert_select "a[href=?]", edit_memo_path(m, memo_directory_id: dir.id)
    assert_includes response.body, "bg-zinc-200 font-medium text-zinc-900"
    assert_includes response.body, m.title
    assert_not_includes response.body, "検索結果"
  end

  test "show from search tag tab stays on memo and syncs tag sidebar" do
    m = memos(:two)
    tag = tags(:two)
    m.update_columns(title: "SidebarSyncTagSearch", body: "body")

    get edit_memo_url(m, sidebar_view: "search", q: "SidebarSyncTagSearch")
    assert_response :success
    assert_select "a", text: "タグ" do |links|
      href = links.first["href"]
      assert_includes href, "sidebar_view=tag"
      assert_includes href, "tag_id=#{tag.id}"
    end

    get edit_memo_url(m, sidebar_view: "tag", tag_id: tag.id)
    assert_response :success
    assert_includes response.body, tag.name
    assert_includes response.body, m.title
    assert_not_includes response.body, "検索結果"
  end

  test "index search respects policy scope" do
    other = memos(:two)
    other.update_columns(
      title: "Peer private note",
      body: "PeerOnlySearchKeyword",
      account_id: accounts(:two).id,
      visibility: Memo.visibilities[:owner_read_write]
    )
    sign_in_as(:one)
    get memos_url(sidebar_view: "search", q: "PeerOnlySearchKeyword")
    assert_response :success
    assert_includes response.body, "該当するメモはありません"
    assert_not_includes response.body, "Peer private note"
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

  test "wiki_completions returns link targets as json" do
    get wiki_completions_memos_url, params: { memo_id: memos(:one).id, q: "Second" }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body.is_a?(Array)
    entry = body.find { |e| e["label"] == "Second memo" }
    assert entry
    assert_equal memos(:two).slug, entry["insert"]
  end

  test "guest cannot access wiki completions" do
    post "/logout"
    get wiki_completions_memos_url, as: :json
    assert_response :redirect
  end

  test "wiki_link_labels returns display labels for targets" do
    two = memos(:two)
    get wiki_link_labels_memos_url,
      params: { memo_id: memos(:one).id, targets: [two.slug, "Second memo", "Missing"] },
      as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal two.title, body[two.slug]["display"]
    assert body[two.slug]["slug"]
    assert_equal two.id, body[two.slug]["memo_id"]
    assert_equal "Second memo", body["Second memo"]["display"]
    assert_not body["Second memo"]["slug"]
    assert_equal two.id, body["Second memo"]["memo_id"]
    assert_not body["Missing"]["resolved"]
    assert_nil body["Missing"]["memo_id"]
  end

  test "edit has memo draft stimulus bindings" do
    get edit_memo_url(memos(:one))
    assert_response :success
    assert_includes response.body, 'data-controller="memo-draft"'
    assert_includes response.body, "memo-body-editor"
    assert_includes response.body, wiki_completions_memos_path(format: :json)
    assert_includes response.body, wiki_link_labels_memos_path(format: :json)
    assert_includes response.body, 'data-controller="memo-directory-dnd"'
    assert_includes response.body, "memo-draft#preventSubmit"
    assert_includes response.body, "memo-draft#suppressEnterSubmit"
    assert_includes response.body, "memo_slug_field"
    assert_select '[data-controller*="memo-body-editor"]'
    assert_select "[data-memo-body-editor-wiki-completions-url-value]"
    assert_select "[data-memo-body-editor-upload-url-value=?]", assets_memo_path(memos(:one))
    assert_select "input[data-memo-body-editor-target='imageInput'][multiple][data-action*='uploadImage']"
    assert_select '[data-controller*="memo-body-editor"] [data-memo-body-editor-target="host"]'
    assert_select '[data-controller*="memo-body-editor"] [data-memo-body-editor-target="field"]'
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
    assert_equal "draft-title-#{memo.id}", memo.slug
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
          title_manual: "1",
          slug_manual: "1"
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
    assert_equal "weird-slug-#{memo.id}", memo.slug
    body = JSON.parse(response.body)
    assert_equal "weird-slug-#{memo.id}", body["slug"]
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

  test "new memo form uses sidebar directory from query param" do
    work = memo_directories(:work)
    get new_memo_url(memo_directory_id: work.id)
    assert_response :success
    assert_includes response.body, "仕事"
    assert_select "input[name='memo[memo_directory_id]'][value='#{work.id}']"
    assert_includes response.body, 'data-memo-draft-target="directory"'
  end

  test "create via json saves memo_directory_id from form body" do
    work = memo_directories(:work)
    home_u_one = memo_directories(:home_u_one)
    assert_difference("Memo.count", 1) do
      post memos_url,
        params: {
          memo: {
            body: "= In work dir\n",
            title_manual: false,
            slug: "",
            memo_directory_id: work.id,
            tag_list: "",
            properties_yaml: "{}"
          }
        },
        as: :json
    end
    assert_response :created
    m = Memo.order(:id).last
    assert_equal work.id, m.memo_directory_id
    assert_not_equal home_u_one.id, m.memo_directory_id
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
    m = Memo.order(:id).last
    assert_equal "from-json-#{m.id}", json["slug"]
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

  test "edit shows wiki link copy button on directory field" do
    get edit_memo_url(memos(:one))
    assert_response :success
    assert_select "#memo_directory_field button[aria-label='Wiki リンクをコピー']"
    assert_includes response.body, "memo-wiki-link-copy"
  end

  test "show renders wiki link to another memo in body" do
    source = memos(:one)
    target = memos(:two)
    source.update_columns(
      file_committed_at: 1.hour.ago,
      body: "= Linked\n\nSee [[#{target.title}]] for more."
    )
    get memo_url(source)
    assert_response :success
    assert_includes response.body, %(href="/memos/#{target.id}")
    assert_includes response.body, target.title
  end

  test "show does not link to memo outside policy scope" do
    source = memos(:one)
    private_memo = memos(:two)
    private_memo.update_columns(
      title: "Secret sibling",
      account_id: accounts(:two).id,
      visibility: Memo.visibilities[:owner_read_write]
    )
    source.update_columns(
      file_committed_at: 1.hour.ago,
      body: "= Linked\n\n[[Secret sibling]]"
    )
    get memo_url(source)
    assert_response :success
    assert_includes response.body, "memo-wiki-broken"
    assert_not_includes response.body, %(href="/memos/#{private_memo.id}")
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
