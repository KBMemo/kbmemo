require "test_helper"

class MemosControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get memos_url
    assert_response :success
  end

  test "shows a memo addressed by its uid" do
    one = memos(:one)
    get "/memos/#{one.uid}"
    assert_response :success
    assert_includes response.body, one.title
  end

  test "uid lookup is case-insensitive" do
    one = memos(:one)
    get "/memos/#{one.uid.downcase}"
    assert_response :success
  end

  test "unknown uid returns not found" do
    get "/memos/#{ULID.generate}"
    assert_response :not_found
  end

  test "index search finds memos by title or body across directories" do
    m = memos(:one)
    m.update_columns(title: "UniqueSearchToken", body: "body")
    get memos_url(sidebar_view: "search", q: "UniqueSearchToken")
    assert_response :success
    assert_includes response.body, m.title
    assert_includes response.body, "検索結果"
    assert_select "search[data-controller='memo-search']"
    assert_select "label.sr-only[for='q']", text: "タイトル・本文を検索"
  end

  test "index redirects legacy q param to search tab" do
    get memos_url(q: "hello")
    assert_redirected_to memos_url(sidebar_view: "search", q: "hello")
  end

  test "history tab lists recently viewed memos" do
    one = memos(:one)
    two = memos(:two)
    get memo_url(two)
    assert_response :success
    travel 1.minute do
      get memo_url(one)
      assert_response :success
    end

    get memos_url(sidebar_view: "history")
    assert_response :success
    assert_includes response.body, "表示履歴"
    assert_match(/#{Regexp.escape(one.title)}[\s\S]*#{Regexp.escape(two.title)}/m, response.body)
  end

  test "history tab preserves order of other memos when reopening from sidebar" do
    one = memos(:one)
    two = memos(:two)
    three = Memo.create!(
      title: "History third memo",
      body: "body",
      memo_directory: memo_directories(:work),
      account: accounts(:one),
      file_committed_at: Time.current
    )

    travel_to Time.zone.parse("2026-01-01 12:00:00") do
      get memo_url(one)
      travel 1.minute
      get memo_url(two)
      travel 1.minute
      get memo_url(three)
      travel 1.minute
      get memo_url(one, sidebar_view: "history")
    end

    assert_response :success
    assert_select "#memos_list_panel #memo_sidebar_memo_list > li", count: 3
    assert_select "#memos_list_panel #memo_sidebar_memo_list > li:nth-child(1) a" do |links|
      assert_includes links.first.text, one.title
    end
    assert_select "#memos_list_panel #memo_sidebar_memo_list > li:nth-child(2) a" do |links|
      assert_includes links.first.text, three.title
    end
    assert_select "#memos_list_panel #memo_sidebar_memo_list > li:nth-child(3) a" do |links|
      assert_includes links.first.text, two.title
    end
    assert_select "#sidebar_row_memo_#{one.id}"
    assert_select "#sidebar_row_memo_#{two.id}"
    assert_select "#sidebar_row_memo_#{three.id}"
    assert_select "#memo_sidebar_memo_list[data-history-memo-ids='#{one.id},#{three.id},#{two.id}']"
    # 履歴リンクの Turbo prefetch は有効。記録は同期リフレッシュ側で open_memo_id を使って行うため、
    # hover prefetch が順序を崩すことはない。
    assert_select "#memos_list_panel a[data-turbo-prefetch='false']", count: 0
  end

  test "history tab clicking C in A B C D order yields C A B D" do
    memo_a = memos(:one)
    memo_b = memos(:two)
    memo_c = Memo.create!(
      title: "History memo C",
      body: "body",
      memo_directory: memo_directories(:work),
      account: accounts(:one),
      file_committed_at: Time.current
    )
    memo_d = Memo.create!(
      title: "History memo D",
      body: "body",
      memo_directory: memo_directories(:work),
      account: accounts(:one),
      file_committed_at: Time.current
    )

    travel_to Time.zone.parse("2026-01-01 12:00:00") do
      get memo_url(memo_d)
      travel 1.minute
      get memo_url(memo_c)
      travel 1.minute
      get memo_url(memo_b)
      travel 1.minute
      get memo_url(memo_a)
      travel 1.minute
      get memo_url(memo_c, sidebar_view: "history")
    end

    assert_response :success
    assert_select "#memo_sidebar_memo_list[data-history-memo-ids='#{memo_c.id},#{memo_a.id},#{memo_b.id},#{memo_d.id}']"
    assert_select "#memos_list_panel #memo_sidebar_memo_list > li:nth-child(1)#sidebar_row_memo_#{memo_c.id}"
    assert_select "#memos_list_panel #memo_sidebar_memo_list > li:nth-child(2)#sidebar_row_memo_#{memo_a.id}"
    assert_select "#memos_list_panel #memo_sidebar_memo_list > li:nth-child(3)#sidebar_row_memo_#{memo_b.id}"
    assert_select "#memos_list_panel #memo_sidebar_memo_list > li:nth-child(4)#sidebar_row_memo_#{memo_d.id}"
  end

  test "show records memo view history" do
    memo = memos(:one)
    assert_difference -> { MemoViewHistory.where(account_id: accounts(:one).id, memo_id: memo.id).count }, 1 do
      get memo_url(memo)
      assert_response :success
    end
  end

  test "show links to the notebook the memo belongs to" do
    memo = memos(:one)
    notebook = notebooks(:one)

    get memo_url(memo)
    assert_response :success
    assert_select "a[href=?]", notebook_path(notebook, memo_id: memo.id), text: notebook.title
  end

  test "show skips memo view history for sidebar sync requests" do
    memo = memos(:one)
    assert_no_difference -> { MemoViewHistory.where(account_id: accounts(:one).id, memo_id: memo.id).count } do
      get memo_url(memo), headers: { "X-Kbmemo-Sidebar-Sync" => "1" }
      assert_response :success
    end
  end

  test "show skips memo view history for turbo prefetch requests" do
    memo = memos(:one)
    assert_no_difference -> { MemoViewHistory.where(account_id: accounts(:one).id, memo_id: memo.id).count } do
      get memo_url(memo), headers: { "X-Sec-Purpose" => "prefetch" }
      assert_response :success
    end
  end

  test "prefetching another memo does not push it above preserved history order on click" do
    memo_a = memos(:one)
    memo_b = memos(:two)
    memo_c = Memo.create!(
      title: "History memo C",
      body: "body",
      memo_directory: memo_directories(:work),
      account: accounts(:one),
      file_committed_at: Time.current
    )
    memo_d = Memo.create!(
      title: "History memo D",
      body: "body",
      memo_directory: memo_directories(:work),
      account: accounts(:one),
      file_committed_at: Time.current
    )

    travel_to Time.zone.parse("2026-01-01 12:00:00") do
      get memo_url(memo_d)
      travel 1.minute
      get memo_url(memo_c)
      travel 1.minute
      get memo_url(memo_b)
      travel 1.minute
      get memo_url(memo_a)
      travel 1.minute
      get memo_url(memo_b), headers: { "X-Sec-Purpose" => "prefetch" }
      get memo_url(memo_c, sidebar_view: "history")
    end

    assert_response :success
    assert_select "#memo_sidebar_memo_list[data-history-memo-ids='#{memo_c.id},#{memo_a.id},#{memo_b.id},#{memo_d.id}']"
    assert_select "#memo_sidebar_memo_list_container #memo_sidebar_memo_list > li:nth-child(2)#sidebar_row_memo_#{memo_a.id}"
  end

  test "sidebar_memo_list moves the open memo to the top for an already-viewed memo" do
    one = memos(:one)
    two = memos(:two)
    three = Memo.create!(
      title: "Sidebar sync third",
      body: "body",
      memo_directory: memo_directories(:work),
      account: accounts(:one),
      file_committed_at: Time.current
    )

    travel_to Time.zone.parse("2026-01-01 12:00:00") do
      get memo_url(one)
      travel 1.minute
      get memo_url(two)
      travel 1.minute
      get memo_url(three) # 順序: three, two, one
    end

    # Turbo の prefetch キャッシュ再利用で本リクエストがサーバーに届かなかったクリック相当。
    # 同期リフレッシュが open_memo_id を先頭へ移動させる。既存メモなので件数は増えない。
    assert_no_difference -> { MemoViewHistory.count } do
      get sidebar_memo_list_memos_url(sidebar_view: "history", open_memo_id: two.id),
        headers: { "X-Kbmemo-Sidebar-Sync" => "1" }
    end
    assert_response :success
    assert_select "#memo_sidebar_memo_list[data-history-memo-ids='#{two.id},#{three.id},#{one.id}']"
    assert_select "#memo_sidebar_memo_list_container #memo_sidebar_memo_list > li:nth-child(1)#sidebar_row_memo_#{two.id}"
  end

  test "sidebar_memo_list records a newly opened memo into history" do
    one = memos(:one)
    fresh = Memo.create!(
      title: "Never viewed yet",
      body: "body",
      memo_directory: memo_directories(:work),
      account: accounts(:one),
      file_committed_at: Time.current
    )

    travel_to Time.zone.parse("2026-01-01 12:00:00") do
      get memo_url(one)
    end

    # prefetch キャッシュ経由で初めて開いたメモも、同期リフレッシュで履歴へ追加される。
    assert_difference -> { MemoViewHistory.where(account_id: accounts(:one).id, memo_id: fresh.id).count }, 1 do
      get sidebar_memo_list_memos_url(sidebar_view: "history", open_memo_id: fresh.id),
        headers: { "X-Kbmemo-Sidebar-Sync" => "1" }
    end
    assert_response :success
    assert_select "#memo_sidebar_memo_list[data-history-memo-ids='#{fresh.id},#{one.id}']"
    assert_select "#memo_sidebar_memo_list_container #memo_sidebar_memo_list > li:nth-child(1)#sidebar_row_memo_#{fresh.id}"
  end

  test "sidebar_memo_list does not record a prefetch refresh" do
    one = memos(:one)
    two = memos(:two)

    travel_to Time.zone.parse("2026-01-01 12:00:00") do
      get memo_url(one)
      travel 1.minute
      get memo_url(two) # 順序: two, one
    end

    # 同期リフレッシュ自体が prefetch された場合は記録しない（順序を崩さない）。
    assert_no_difference -> { MemoViewHistory.maximum(:view_sequence) } do
      get sidebar_memo_list_memos_url(sidebar_view: "history", open_memo_id: one.id),
        headers: { "X-Kbmemo-Sidebar-Sync" => "1", "X-Sec-Purpose" => "prefetch" }
    end
    assert_response :success
    assert_select "#memo_sidebar_memo_list[data-history-memo-ids='#{two.id},#{one.id}']"
  end

  test "show from search keeps memo open without syncing directory sidebar" do
    m = memos(:one)
    dir = m.memo_directory
    m.update_columns(title: "SidebarSyncSearch", body: "body")

    get edit_memo_url(m, sidebar_view: "search", q: "SidebarSyncSearch")
    assert_response :success
    assert_select "a", text: "ディレクトリ" do |links|
      href = links.first["href"]
      assert_match %r{/memos/#{m.id}/edit}, href
      assert_not_includes href, "memo_directory_id=#{dir.id}"
      assert_not_includes href, "sidebar_view=search"
    end

    get edit_memo_url(m, memo_directory_id: dir.id)
    assert_response :success
    assert_select "a[href=?]", edit_memo_path(m, memo_directory_id: dir.id)
    assert_includes response.body, "kb-sidebar-nav"
    assert_includes response.body, "is-active"
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

  test "draft directory change does not refresh sidebar directory selection" do
    m = memos(:one)
    work = m.memo_directory
    share_u1 = MemoDirectory.find_by!(full_path: "share/u-1")

    get edit_memo_url(m, memo_directory_id: work.id)
    assert_response :success

    patch draft_memo_url(m, memo_directory_id: work.id),
      params: { memo: { memo_directory_id: share_u1.id } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_equal share_u1.id, m.reload.memo_directory_id

    list_panel = response.body[/target="memos_list_panel"><template>(.*)<\/template>/m, 1]
    assert list_panel, "expected memos_list_panel turbo stream"
    assert_includes list_panel, %(href="/memos?memo_directory_id=#{work.id}"><span class="truncate">仕事</span></a>)
    assert_includes list_panel, "is-active"
    assert_not_includes list_panel, %(href="/memos?memo_directory_id=#{share_u1.id}" class="kb-sidebar-nav block rounded-md px-2 py-1.5 text-sm transition focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--kb-border-strong)] focus-visible:ring-offset-2 is-active)
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
    assert_equal memos(:two).uid, entry["insert"]
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
    assert_equal two.uid, body[two.slug]["memo_uid"]
    assert_equal "Second memo", body["Second memo"]["display"]
    assert_not body["Second memo"]["slug"]
    assert_equal two.id, body["Second memo"]["memo_id"]
    assert_not body["Missing"]["resolved"]
    assert_nil body["Missing"]["memo_id"]
  end

  test "edit shows a back link to the notebook the memo belongs to" do
    memo = memos(:one)
    notebook = notebooks(:one)

    get edit_memo_url(memo)
    assert_response :success
    assert_select "a[href=?]", notebook_path(notebook, memo_id: memo.id)
  end

  test "edit has memo draft stimulus bindings" do
    get edit_memo_url(memos(:one))
    assert_response :success
    assert_includes response.body, 'data-controller="memo-draft"'
    assert_includes response.body, "memo-body-editor"
    assert_includes response.body, wiki_completions_memos_path(format: :json)
    assert_includes response.body, wiki_link_labels_memos_path(format: :json)
    assert_select '[data-controller~="memo-directory-dnd"]'
    assert_includes response.body, "memo-draft#preventSubmit"
    assert_includes response.body, "memo-draft#suppressEnterSubmit"
    assert_select "button.memo-directory-nav-summary a", count: 0
    assert_select "button.memo-directory-nav-summary + .memo-directory-nav-row"
    assert_select "img.kb-avatar[loading='eager'][fetchpriority='low'][width='28'][height='28']"
    assert_includes response.body, "memo_slug_field"
    assert_match(/data-memo[-_]draft[-_]tag[-_]catalog[-_]value=.*Ideas/, response.body)
    assert_select '[data-controller*="memo-body-editor"]'
    assert_select "[data-memo-body-editor-wiki-completions-url-value]"
    assert_select "[data-memo-body-editor-upload-url-value=?]", assets_memo_path(memos(:one))
    assert_select "input[data-memo-body-editor-target='imageInput'][multiple][data-action*='uploadImage']"
    assert_includes response.body, "画像を挿入"
    assert_includes response.body, "ライブプレビュー"
    assert_select '[data-controller*="memo-body-editor"] [data-memo-body-editor-target="host"]'
    assert_select '[data-controller*="memo-body-editor"] [data-memo-body-editor-target="field"]'
    assert_select "[role='tablist'][aria-label='編集モード'][data-action*='editModeTabKeydown']"
    assert_select "button#memo_body_editor_tab_source[role='tab'][aria-selected='true'][aria-controls='memo_body_editor_panel_source'][tabindex='0']"
    assert_select "button#memo_body_editor_tab_wysiwyg[role='tab'][aria-selected='false'][aria-controls='memo_body_editor_panel_wysiwyg'][tabindex='-1']"
    assert_select "#memo_body_editor_panel_source[role='tabpanel'][aria-labelledby='memo_body_editor_tab_source']"
    assert_select "#memo_body_editor_panel_wysiwyg[role='tabpanel'][aria-labelledby='memo_body_editor_tab_wysiwyg']"
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
    # 一度コミット済み（file_committed_at あり）のメモは、明示指定した slug を優先して保持する。
    assert_equal memo_global_slug("draft-slug", memo), memo.slug
    assert_equal({ "k" => 1 }, memo.properties)
    assert_includes memo.tags.map(&:name), "draft-tag"
    assert_not memo.title_manual
    body = JSON.parse(response.body)
    assert_equal memo.title, body["title"]
  end

  test "draft derives slug from title for an uncommitted memo when slug is blank" do
    memo = Memo.new(
      title: "Tmp",
      body: "tmp",
      memo_directory: memo_directories(:work),
      account_id: accounts(:one).id
    )
    memo.save!
    assert_nil memo.file_committed_at

    patch draft_memo_url(memo),
      params: { memo: { body: "= Derived heading", title_manual: false, slug: "" } },
      as: :json
    assert_response :success
    memo.reload
    assert_equal "Derived heading", memo.title
    # 初回コミット前 + 自動モード（slug 空）はタイトルから派生する。
    assert_equal memo_global_slug("derived-heading", memo), memo.slug
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

  test "update via turbo stream replaces editor without full page redirect" do
    memo = memos(:one)
    patch memo_url(memo),
      params: {
        memo: {
          title: "Turbo commit title",
          body: "= Turbo commit\n\nParagraph.",
          slug: "turbo-commit-slug",
          title_manual: "1",
          slug_manual: "1"
        }
      },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes @response.body, %(turbo-stream action="replace" target="memos_editor_scroll")
    assert_includes @response.body, %(turbo-stream action="replace" target="memos_list_panel")
    assert_includes @response.body, %(turbo-stream action="replace" target="flash-live")
    assert_includes @response.body, %(turbo-stream action="remove" target="memo_ai_sidebar_region")
    assert_includes @response.body, "Turbo commit title"
    assert_includes @response.body, "Git に記録"
    assert memo.reload.file_committed_at.present?
  end

  test "commit from show persists current db memo to git" do
    memo = memos(:one)
    t = 1.hour.ago.change(usec: 0)
    memo.update_columns(
      file_committed_at: t,
      updated_at: t + 1.minute,
      body: "= Changed on show\n\nParagraph."
    )
    assert memo.reload.display_as_draft?

    patch commit_memo_path(memo)
    assert_redirected_to memo_path(memo)
    follow_redirect!
    assert_select "#flash-live.fixed"
    assert_select "[data-flash-notice-target='message']", text: /Git に記録/
    assert_select "button[aria-label='メッセージを閉じる'][data-action='flash-notice#dismiss']"
    memo.reload
    assert_not memo.display_as_draft?
    repo = MemoRepository.new
    assert_includes repo.absolute_path_for(memo).read, "Changed on show"
  end

  test "show displays commit button when memo is draft" do
    memo = memos(:one)
    t = 1.hour.ago.change(usec: 0)
    memo.update_columns(file_committed_at: t, updated_at: t + 1.minute, body: "= Draft body\n\nx")

    get memo_path(memo)
    assert_response :success
    assert_select "form[action=?][method=?]", commit_memo_path(memo), "post" do
      assert_select "input[name=_method][value=patch]", count: 1
      assert_select "button[type=submit]", text: "コミット"
    end
  end

  test "show hides commit button when memo is committed" do
    memo = memos(:two)
    t = 1.hour.ago.change(usec: 0)
    memo.update_columns(file_committed_at: t, updated_at: t)

    get memo_path(memo)
    assert_response :success
    assert_select "form[action=?]", commit_memo_path(memo), count: 0
  end

  test "show attaches memo show context menu stimulus data" do
    memo = memos(:one)

    get memo_path(memo)
    assert_response :success
    assert_select "##{dom_id(memo)}[data-controller~='memo-show-context-menu']"
    assert_select "##{dom_id(memo)}[data-action='contextmenu->memo-show-context-menu#open']"
    assert_select "##{dom_id(memo)}[data-memo-show-context-menu-edit-url-value]"
    assert_select "##{dom_id(memo)}[data-memo-show-context-menu-can-edit-value='true']"
  end

  test "revert_draft restores memo fields from last git commit" do
    memo = memos(:one)
    repo = MemoRepository.new
    committed_at = 2.hours.ago.change(usec: 0)
    memo.update_columns(
      title: "Committed title",
      body: "= Committed title\n\nCommitted paragraph.",
      slug: memo_global_slug("committed-title", memo),
      file_committed_at: committed_at,
      updated_at: committed_at
    )
    repo.write_and_commit!(memo)

    patch draft_memo_url(memo),
      params: { memo: { body: "= Draft title\n\nDraft paragraph.", title: "Draft title", title_manual: true } },
      as: :json
    assert_response :success
    assert memo.reload.display_as_draft?

    patch revert_draft_memo_url(memo), as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal edit_memo_path(memo), data["edit_path"]

    memo.reload
    assert_not memo.display_as_draft?
    assert_equal committed_at.to_i, memo.updated_at.to_i
    assert_equal "Committed title", memo.title
    assert_includes memo.body, "Committed paragraph."
    assert_includes repo.absolute_path_for(memo).read, "Committed paragraph."
    assert_not_includes repo.absolute_path_for(memo).read, "Draft paragraph."
  end

  test "revert_draft rejects memo without file commit" do
    memo = memos(:one)
    memo.update_column(:file_committed_at, nil)
    patch revert_draft_memo_url(memo), as: :json
    assert_response :unprocessable_entity
  end

  test "edit shows revert draft button when re-editing committed memo" do
    memo = memos(:one)
    t = 1.hour.ago.change(usec: 0)
    memo.update_columns(file_committed_at: t, updated_at: t)
    patch draft_memo_url(memo), params: { memo: { body: "= Changed\n\nx" } }, as: :json
    assert memo.reload.display_as_draft?

    get edit_memo_url(memo)
    assert_response :success
    assert_includes response.body, "ドラフトを破棄"
  end

  test "edit hides revert draft button until autosave marks memo as draft" do
    memo = memos(:one)
    t = 1.hour.ago.change(usec: 0)
    memo.update_columns(file_committed_at: t, updated_at: t)

    get edit_memo_url(memo)
    assert_response :success
    assert_select "#memo_form_actions button[data-memo-draft-target='discardDraftButton'].hidden"

    patch draft_memo_url(memo),
      params: { memo: { body: "= Changed\n\nx" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    actions = response.body[/target="memo_form_actions"><template>(.*)<\/template>/m, 1]
    assert actions, "expected memo_form_actions turbo stream"
    assert_includes actions, "ドラフトを破棄"
    assert_match(/data-memo-draft-target="discardDraftButton"/, actions)
    assert_no_match(/data-memo-draft-target="discardDraftButton"[^>]*class="[^"]*\bhidden\b/, actions)
  end

  test "draft turbo stream links commit button to memo edit form" do
    memo = memos(:one)
    t = 1.hour.ago.change(usec: 0)
    memo.update_columns(file_committed_at: t, updated_at: t)
    get edit_memo_url(memo)
    assert_response :success

    patch draft_memo_url(memo),
      params: { memo: { body: "= Changed\n\nx" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success

    actions = response.body[/target="memo_form_actions"><template>(.*)<\/template>/m, 1]
    assert actions, "expected memo_form_actions turbo stream when draft state changes"
    assert_match(/data-memo-commit="true"/, actions)
    assert_match(/type="submit"/, actions)
    assert_match(/form="#{dom_id(memo, :edit_form)}"/, actions)
  end

  test "draft autosave for uncommitted memo does not replace form actions" do
    memo = memos(:one)
    memo.update_column(:file_committed_at, nil)
    get edit_memo_url(memo)
    assert_response :success

    patch draft_memo_url(memo),
      params: { memo: { body: "= Clip title\n\nClipped body." } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_not_includes response.body, 'target="memo_form_actions"'
    assert_includes response.body, "memo_title_field"
  end

  test "edit uncommitted memo keeps delete and commit outside nested forms" do
    memo = memos(:one)
    memo.update_column(:file_committed_at, nil)
    get edit_memo_url(memo)
    assert_response :success

    form_id = dom_id(memo, :edit_form)
    assert_select "form##{form_id}" do
      assert_select "#memo_form_actions", count: 0
      assert_select "button[data-memo-commit='true']", count: 0
      assert_select "button", text: "削除", count: 0
    end
    assert_select "#memo_form_actions button[data-memo-commit='true'][form='#{form_id}']", text: "コミット"
    assert_select "#memo_form_actions button", text: "削除"
    assert_select "#memo_form_actions input[name='_method'][value='delete']"
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
    assert_equal memo_global_slug("weird-slug", memo), memo.slug
    body = JSON.parse(response.body)
    assert_equal memo_global_slug("weird-slug", memo), body["slug"]
  end

  test "draft json returns saved_at for multi-tab sync" do
    memo = memos(:one)
    patch draft_memo_url(memo),
      params: { memo: { body: "= Updated\n\nBody." } },
      as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert data["saved_at"].present?
    memo.reload
    assert_includes memo.body, "Updated"
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
    assert_select "button[disabled][title*='コミット']", text: "画像を挿入"
    assert_select "input[data-memo-body-editor-target='imageInput']", count: 0
    assert_select "#memo_form_actions button", text: "削除", count: 0
    assert_select "#memo_form_actions button[data-memo-commit='true'].hidden", count: 1
    assert_select ".memo-draft-shell [data-memo-draft-target='formActionsChrome'].hidden"
  end

  test "new memo form renders empty title and disables turbo cache" do
    get new_memo_url
    assert_response :success
    assert_select "input#memo_title[value='']"
    assert_select "input#memo_slug[value='']"
    assert_select "textarea#memo_body", text: ""
    assert_select "textarea[name='memo[properties_yaml]']", text: ""
    assert_select "input[name='memo[tag_list]'][value='']"
    assert_select "select[name='memo[visibility]'] option[selected][value='owner_read_write']"
    assert_select "select[name='memo[memo_group_id]'] option[value='']", text: "（なし）"
    assert_select "select[name='memo[memo_group_id]'] option[selected][value]:not([value=''])", count: 0
    assert_match(/data-turbo[-_]cache="false"/, response.body)
    assert_includes response.body, 'data-memo-draft-create-url-value'
    assert_includes response.body, 'data-memo-draft-initial-form-value'
    assert_not_includes response.body, "data-memo_draft_create_url_value"
    assert_select ".memo-draft-shell[data-controller~='memo-draft']"
    assert_select ".memo-draft-shell [data-memo-draft-target='formActionsChrome']"
    assert_select "form#new_memo_form [data-memo-draft-target='formActionsChrome']", count: 0
    assert_select "summary[aria-label='タイトル同期の説明'][aria-describedby='memo-title-hint']"
    assert_select "#memo-title-hint", text: /本文1行目/
    assert_select "summary[aria-label='スラッグ同期の説明'][aria-describedby='memo-slug-hint']"
    assert_select "#memo-slug-hint", text: /タイトルと同期/
    assert_select "summary[aria-label='公開範囲の説明'][aria-describedby='memo-visibility-hint']"
    assert_select "#memo-visibility-hint", text: /共有グループ/
    assert_select "button[aria-label='Wiki リンクの説明を表示'][aria-controls='memo-wiki-link-hint'][aria-expanded='false']"
  end

  test "directory sidebar hint has an accessible description" do
    get memos_url(memo_directory_id: memo_directories(:work).id)
    assert_response :success
    assert_select "summary[aria-label='メモ移動方法の説明'][aria-describedby='memo-directory-move-hint']"
    assert_select "#memo-directory-move-hint", text: /ドラッグ/
    assert_select "#memo-directory-move-hint", text: /キーボード操作/
    assert_select "[data-memo-directory-dnd-handle][aria-hidden='true'][draggable='true']"
    assert_select "[data-memo-directory-dnd-handle][role]", count: 0
    assert_select "[data-memo-directory-dnd-handle][tabindex]", count: 0
  end

  test "directory sidebar shows disclosure controls on top-level buckets" do
    get memos_url
    assert_response :success

    %w[Home Share Public System].each do |label|
      assert_select "#memos_list_panel a span", text: label
      assert_select "#memos_list_panel [data-memo-directory-nav-branch][data-memo-directory-nav-open='true'] > button[aria-label='#{label} の子ディレクトリを開閉']"
    end
    assert_select "#memos_list_panel [data-memo-directory-nav-branch] > button.memo-directory-nav-summary + .memo-directory-nav-row"
  end

  test "edit uncommitted memo shows delete and commit actions" do
    memo = memos(:one)
    memo.update_column(:file_committed_at, nil)
    get edit_memo_url(memo)
    assert_response :success
    assert_select "#memo_form_actions button", text: "削除"
    assert_select "#memo_form_actions button[data-memo-commit='true']", text: "コミット"
    assert_select "#memo_form_actions button", text: "ドラフトを破棄", count: 0
  end

  test "edit uncommitted delete is nested form outside edit form for turbo" do
    memo = memos(:one)
    memo.update_column(:file_committed_at, nil)
    form_id = dom_id(memo, :edit_form)
    get edit_memo_url(memo)
    assert_response :success
    assert_select "form##{form_id}" do
      assert_select "button", text: "削除", count: 0
    end
    assert_select "#memo_form_actions form[method='post'][action^='#{memo_path(memo)}']" do
      assert_select "input[name='_method'][value='delete']"
      assert_select "button", text: "削除"
    end
  end

  test "destroy uncommitted memo via turbo stream removes sidebar row and clears editor" do
    memo = memos(:one)
    memo.update_column(:file_committed_at, nil)
    work = memo_directories(:work)
    memo.update!(memo_directory: work)
    tag = tags(:one)
    memo.tags = [tag]

    assert_difference("Memo.count", -1) do
      delete memo_path(memo, sidebar_view: "tag", tag_id: tag.id),
        headers: { Accept: "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes @response.body, %(turbo-stream action="remove" target="sidebar_row_memo_#{memo.id}")
    assert_includes @response.body, %(turbo-stream action="replace" target="memos_list_panel")
    assert_includes @response.body, %(turbo-stream action="replace" target="memos_editor_scroll")
    assert_select "#sidebar_row_memo_#{memo.id}", count: 0
  end

  test "destroy memo redirects with sidebar nav query" do
    memo = memos(:one)
    work = memo_directories(:work)
    memo.update!(memo_directory: work)

    assert_difference("Memo.count", -1) do
      delete memo_path(memo, memo_directory_id: work.id)
    end
    assert_redirected_to memos_path(memo_directory_id: work.id)
  end

  test "edit disables image insert when memo not committed to git" do
    memo = memos(:one)
    memo.update_column(:file_committed_at, nil)
    get edit_memo_url(memo)
    assert_response :success
    assert_select "button[disabled][title*='コミット']", text: "画像を挿入"
    assert_select "input[data-memo-body-editor-target='imageInput']", count: 0
    assert_not_includes response.body, assets_memo_path(memo)
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
    assert json["update_url"].present?
    assert json["form_dom_id"].present?
    m = Memo.order(:id).last
    assert_equal memo_global_slug("from-json", m), json["slug"]
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

  test "edit shows sidebar open button on directory field" do
    get edit_memo_url(memos(:one))
    assert_response :success
    assert_select "#memo_directory_field button[aria-label='サイドバーでこのディレクトリを表示']"
    assert_includes response.body, "memo-directory-sidebar-open"
    assert_includes response.body, "panel-left-open"
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
    assert_includes response.body, %(href="/memos/#{target.uid}")
    assert_includes response.body, target.title
  end

  test "show renders backlinks to memos linking to current memo" do
    target = memos(:two)
    source = memos(:one)
    source.update_columns(
      file_committed_at: 1.hour.ago,
      body: "See [[#{target.title}]] for more."
    )
    MemoWikiLinkIndex.rebuild_for(source)
    get memo_url(target)
    assert_response :success
    assert_includes response.body, "バックリンク"
    assert_includes response.body, %(href="/memos/#{source.id}")
    assert_includes response.body, source.title
  end

  test "edit renders backlinks to memos linking to current memo" do
    target = memos(:two)
    source = memos(:one)
    source.update_columns(body: "See [[#{target.slug}]] for more.")
    MemoWikiLinkIndex.rebuild_for(source)
    get edit_memo_url(target)
    assert_response :success
    assert_includes response.body, "バックリンク"
    assert_includes response.body, %(href="/memos/#{source.id}")
    assert_includes response.body, source.title
  end

  test "show hides backlinks section when none exist" do
    target = memos(:two)
    target.update_columns(body: "= Solo")
    get memo_url(target)
    assert_response :success
    assert_not_includes response.body, "バックリンク"
  end

  test "show displays memo directory path in metadata" do
    memo = memos(:one)
    memo.update_columns(file_committed_at: 1.hour.ago, properties: { "priority" => 1 })
    get memo_url(memo)
    assert_response :success
    assert_includes response.body, memo.memo_directory.labeled_path_from_root
    assert_includes response.body, memo.slug
    assert_select "img.kb-avatar[loading='eager'][fetchpriority='low'][width='36'][height='36']"
    assert_select "button[aria-label='プロパティ全文を表示'][aria-controls='memo-properties-panel'][aria-expanded='false']"
    # 編集可能な所有者はディレクトリ picker が表示される（選択中ディレクトリを反映）。
    assert_select "input#memo_show_directory_id_#{memo.id}[value=?]", memo.memo_directory_id.to_s
    assert_select "#memo_show_directory_id_#{memo.id}_directory_picker_panel[data-memo-directory-parent-picker-target='panel']" do
      %w[Home Share Public System].each do |label|
        assert_select ".kb-directory-picker-branch > .kb-directory-picker-caret[aria-label='#{label} の子ディレクトリを開閉']"
        assert_select ".kb-directory-picker-branch > .kb-directory-picker-row", text: label
      end
    end
  end

  test "show shows directory path link for a viewer who cannot edit" do
    memo = Memo.create!(
      title: "PublicDirShown",
      body: "body",
      memo_directory: memo_directories(:public_u_one),
      account_id: accounts(:one).id,
      visibility: :public_everyone
    )
    t = 1.hour.ago.change(usec: 0)
    memo.update_columns(file_committed_at: t, updated_at: t)
    sign_in_as(:two)
    get memo_url(memo)
    assert_response :success
    assert_select "a[href=?]", memo_path(memo, memo_directory_id: memo.memo_directory_id),
      text: memo.memo_directory.labeled_path_from_root
  end

  test "sidebar shows open memo directory path and syncs directory tab without query param" do
    memo = memos(:one)
    dir = memo.memo_directory

    get edit_memo_url(memo)
    assert_response :success
    assert_select "#memos_list_panel a[href=?]", edit_memo_path(memo, memo_directory_id: dir.id),
      text: dir.labeled_path_from_root
    assert_includes response.body, %(href="/memos?memo_directory_id=#{dir.id}"><span class="truncate">仕事</span></a>)
  end

  test "sidebar shows open memo directory path on search tab without syncing directory nav" do
    memo = memos(:one)
    dir = memo.memo_directory
    memo.update_columns(title: "SidebarDirDisplay", body: "body")

    get edit_memo_url(memo, sidebar_view: "search", q: "SidebarDirDisplay")
    assert_response :success
    assert_select "#memos_list_panel a[href=?]", edit_memo_path(memo, memo_directory_id: dir.id),
      text: dir.labeled_path_from_root
    assert_select "a", text: "ディレクトリ" do |links|
      href = links.first["href"]
      assert_match %r{/memos/#{memo.id}/edit}, href
      assert_not_includes href, "memo_directory_id=#{dir.id}"
    end
  end

  test "show displays board link when memo is on kanban board" do
    memo = memos(:one)
    board = boards(:one)
    column = board_columns(:one_todo)
    memo.update_columns(
      board_id: board.id,
      kanban_column_id: column.id,
      kanban_position: 0,
      file_committed_at: 1.hour.ago
    )
    get memo_url(memo)
    assert_response :success
    assert_select "a[href=?]", board_path(board), text: board.title
  end

  test "show tag links open sidebar tag tab" do
    # 編集可能な所有者はタグが入力 UI になるため、閲覧専用ユーザーでチップのリンクを検証する。
    memo = Memo.new(
      title: "PublicTagged",
      body: "body",
      memo_directory: memo_directories(:public_u_one),
      account_id: accounts(:one).id,
      visibility: :public_everyone
    )
    memo.assign_tags_from_list("Ideas")
    memo.save!
    t = 1.hour.ago.change(usec: 0)
    memo.update_columns(file_committed_at: t, updated_at: t)
    tag = memo.tags.first!
    sign_in_as(:two)
    get memo_url(memo)
    assert_response :success
    assert_select "a[href=?]", memo_path(memo, sidebar_view: "tag", tag_id: tag.id), text: tag.name
  end

  test "create memo from wiki link body derives title" do
    dir = memo_directories(:work)
    assert_difference -> { Memo.count }, 1 do
      post memos_url, params: {
        memo: {
          body: "= Missing memo\n\n",
          memo_directory_id: dir.id,
          slug: "",
          slug_manual: false,
          title_manual: false,
          tag_list: "",
          properties_yaml: "{}"
        }
      }, as: :json
    end
    assert_response :created
    memo = Memo.order(:id).last
    assert_equal "Missing memo", memo.title
    assert_equal "= Missing memo\n\n", memo.body
  end

  test "show renders broken wiki link as create button for signed in user" do
    source = memos(:one)
    source.update_columns(
      file_committed_at: 1.hour.ago,
      body: "= Linked\n\n[[Brand new topic]]"
    )
    get memo_url(source)
    assert_response :success
    assert_includes response.body, 'data-wiki-target="Brand new topic"'
    assert_includes response.body, 'data-action="memo-wiki-create#create"'
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

  test "manage renders directory tree and memos for the selected directory" do
    get manage_memos_url(memo_directory_id: memo_directories(:work).id)
    assert_response :success
    assert_includes response.body, "ディレクトリ・メモ管理"
    assert_includes response.body, memos(:one).title
    assert_includes response.body, memos(:two).title
  end

  test "bulk_add_tags adds tags to the selected memos while keeping existing ones" do
    existing_one = memos(:one).tags.pluck(:name)
    patch bulk_add_tags_memos_url, params: {
      memo_ids: [ memos(:one).id, memos(:two).id ],
      tag_list: "alpha, beta"
    }
    assert_response :redirect
    one_tags = memos(:one).reload.tags.pluck(:name)
    assert_includes one_tags, "alpha"
    assert_includes one_tags, "beta"
    existing_one.each { |name| assert_includes one_tags, name }

    two_tags = memos(:two).reload.tags.pluck(:name)
    assert_includes two_tags, "alpha"
    assert_includes two_tags, "beta"
  end

  test "bulk_remove_tags removes only the matching tags" do
    memo = memos(:one)
    memo.assign_tags_from_list("keep, drop")
    memo.save!

    patch bulk_remove_tags_memos_url, params: { memo_ids: [ memo.id ], tag_list: "drop" }
    assert_response :redirect
    assert_equal %w[keep], memo.reload.tags.pluck(:name)
  end

  test "bulk_move_directory moves the selected memos" do
    memo = Memo.create!(title: "Bulk move memo", body: "x", memo_directory: memo_directories(:work), account_id: accounts(:one).id)
    target = memo_directories(:home_u_one)
    patch bulk_move_directory_memos_url, params: {
      memo_ids: [ memo.id ],
      target_directory_id: target.id
    }
    assert_response :redirect
    assert_equal target.id, memo.reload.memo_directory_id
  end

  test "bulk_move_directory rejects top-level buckets" do
    memo = Memo.create!(title: "Bulk reject memo", body: "x", memo_directory: memo_directories(:work), account_id: accounts(:one).id)
    patch bulk_move_directory_memos_url, params: {
      memo_ids: [ memo.id ],
      target_directory_id: memo_directories(:home).id
    }
    assert_response :redirect
    assert_equal memo_directories(:work).id, memo.reload.memo_directory_id
  end

  test "bulk_add_to_notebook adds the selected memos to the notebook" do
    notebook = notebooks(:one)
    post bulk_add_to_notebook_memos_url, params: {
      memo_ids: [ memos(:one).id ],
      notebook_id: notebook.id
    }
    assert_response :redirect
    assert NotebookMemo.exists?(notebook_id: notebook.id, memo_id: memos(:one).id)
  end

  test "bulk actions skip memos the user cannot edit" do
    other = Memo.create!(
      title: "Other account memo",
      body: "body",
      memo_directory: memo_directories(:home_u_two),
      account_id: accounts(:two).id
    )
    patch bulk_add_tags_memos_url, params: { memo_ids: [ other.id ], tag_list: "x" }
    assert_response :redirect
    assert_empty other.reload.tags
  end

  test "render_diagram returns sanitized svg for a plantuml source block" do
    sign_in_as(:one)
    memo = memos(:one)
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><text>uml</text></svg>'
    with_stubbed_kroki(svg) do
      post render_diagram_memo_url(memo),
        params: { engine: "plantuml", source: "@startuml\nA -> B\n@enduml" },
        as: :json
    end
    assert_response :success
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "MemoSvgSanitizer", response.headers["X-Kbmemo-Svg-Sanitized"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal true, response.parsed_body["sanitized"]
    assert_equal svg, response.parsed_body["svg"]
  end

  test "render_diagram returns sanitized svg for an svg source block" do
    sign_in_as(:one)
    memo = memos(:one)
    source = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
        <circle r="10"/>
        <script>alert(1)</script>
      </svg>
    SVG
    post render_diagram_memo_url(memo),
      params: { engine: "svg", source: source },
      as: :json
    assert_response :success
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "MemoSvgSanitizer", response.headers["X-Kbmemo-Svg-Sanitized"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal true, response.parsed_body["sanitized"]
    body = response.parsed_body["svg"]
    assert_includes body, "<circle"
    assert_not_includes body, "script"
  end

  test "render_diagram rejects invalid svg source" do
    sign_in_as(:one)
    post render_diagram_memo_url(memos(:one)),
      params: { engine: "svg", source: "not svg" },
      as: :json
    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?
  end

  test "render_diagram rejects an unsupported engine" do
    sign_in_as(:one)
    post render_diagram_memo_url(memos(:one)),
      params: { engine: "ruby", source: "puts 1" },
      as: :json
    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?
  end

  test "render_diagram rejects a blank source" do
    sign_in_as(:one)
    post render_diagram_memo_url(memos(:one)),
      params: { engine: "mermaid", source: "   " },
      as: :json
    assert_response :unprocessable_entity
  end

  test "render_diagram is not found for memos the user cannot view" do
    sign_in_as(:two)
    private_memo = Memo.create!(
      title: "Private",
      body: "secret",
      memo_directory: memo_directories(:work),
      account_id: accounts(:one).id,
      visibility: :owner_read_write
    )
    post render_diagram_memo_url(private_memo),
      params: { engine: "plantuml", source: "@startuml\nA->B\n@enduml" },
      as: :json
    assert_response :not_found
  end

  test "memo body wires the code-block-tools controller with a render url" do
    sign_in_as(:one)
    get memo_url(memos(:one))
    assert_response :success
    assert_includes response.body, "code-block-tools"
    assert_includes response.body, "data-code-block-tools-render-url-value"
  end
end
