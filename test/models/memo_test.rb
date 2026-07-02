# == Schema Information
#
# Table name: memos
#
#  id                :bigint           not null, primary key
#  body              :text             default(""), not null
#  file_committed_at :datetime
#  kanban_position   :integer          default(0), not null
#  properties        :jsonb            not null
#  slug              :string
#  slug_manual       :boolean          default(FALSE), not null
#  title             :string           not null
#  title_manual      :boolean          default(FALSE), not null
#  uid               :string           not null
#  visibility        :integer          default("owner_read_write"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  board_id          :integer
#  kanban_column_id  :integer
#  memo_directory_id :integer          not null
#  memo_group_id     :integer
#
# Indexes
#
#  index_memos_on_account_id         (account_id)
#  index_memos_on_board_id           (board_id)
#  index_memos_on_kanban_column_id   (kanban_column_id)
#  index_memos_on_memo_directory_id  (memo_directory_id)
#  index_memos_on_memo_group_id      (memo_group_id)
#  index_memos_on_slug               (slug) UNIQUE
#  index_memos_on_uid                (uid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (board_id => boards.id)
#  fk_rails_...  (kanban_column_id => board_columns.id)
#  fk_rails_...  (memo_directory_id => memo_directories.id)
#  fk_rails_...  (memo_group_id => memo_groups.id)
#
require "test_helper"

class MemoTest < ActiveSupport::TestCase
  test "derived_title_from_body strips leading equals and uses first line" do
    assert_equal "Hello", Memo.derived_title_from_body("= Hello\n\nMore")
    assert_equal "Hello", Memo.derived_title_from_body("=== Hello")
    assert_equal "Plain", Memo.derived_title_from_body("Plain\nother")
    assert_equal Memo::TITLE_PLACEHOLDER, Memo.derived_title_from_body("")
    assert_equal Memo::TITLE_PLACEHOLDER, Memo.derived_title_from_body("\n\n")
  end

  test "title stays manual when user sets title different from derived" do
    m = Memo.new(
      body: "Line1\nLine2",
      title: "Custom",
      title_manual: false,
      account: accounts(:one),
      memo_directory: memo_directories(:work)
    )
    m.valid?
    assert m.title_manual?
    assert_equal "Custom", m.title
  end

  test "title syncs from body when not manual" do
    m = Memo.new(
      body: "= Doc title\n\nx",
      title_manual: false,
      account: accounts(:one),
      memo_directory: memo_directories(:work)
    )
    m.valid?
    assert_not m.title_manual?
    assert_equal "Doc title", m.title
  end

  test "placeholder title is treated as unfilled" do
    m = Memo.new(
      body: "",
      title: Memo::TITLE_PLACEHOLDER,
      title_manual: true,
      account: accounts(:one),
      memo_directory: memo_directories(:work)
    )
    m.valid?
    assert m.title_unfilled?
    assert_equal Memo::TITLE_PLACEHOLDER, m.title
  end

  test "search_text matches title or body case insensitively" do
    m1 = memos(:one)
    m1.update_columns(title: "Alpha Note", body: "zzz")
    m2 = memos(:two)
    m2.update_columns(title: "Other", body: "contains beta here")

    ids = Memo.search_text("alpha").pluck(:id)
    assert_includes ids, m1.id
    assert_not_includes ids, m2.id

    ids = Memo.search_text("BETA").pluck(:id)
    assert_includes ids, m2.id
    assert_not_includes ids, m1.id
  end

  test "search_text uses pgroonga when extension is enabled" do
    skip "PGroonga is not enabled in this database" unless Memo.pgroonga_search?

    m1 = memos(:one)
    m1.update_columns(title: "京都旅行", body: "清水寺と伏見稲荷")
    m2 = memos(:two)
    m2.update_columns(title: "Ruby メモ", body: "each の使い方")

    ids = Memo.search_text("清水寺").pluck(:id)
    assert_includes ids, m1.id
    assert_not_includes ids, m2.id
  end

  test "rejects memo_directory at top level bucket" do
    m = memos(:one)
    m.memo_directory = memo_directories(:home)
    assert_not m.valid?
    assert_includes m.errors[:memo_directory].join, "Home"
  end

  test "derived_slug_from_title parameterizes title" do
    assert_equal "hello-world", Memo.derived_slug_from_title("Hello World")
    assert_nil Memo.derived_slug_from_title(Memo::TITLE_PLACEHOLDER)
    assert_nil Memo.derived_slug_from_title("")
  end

  test "derived_slug_from_title uses MeCab romaji for Japanese when available" do
    m = memos(:one)
    slug = Memo.derived_slug_from_title("はじめに", m)
    if MemoMecabRomaji.romaji_slug_from("はじめに").present?
      assert_equal "hajime-ni", slug
    else
      assert_equal "memo", slug
    end
  end

  test "derived_slug_from_title keeps Japanese when title mixes ASCII and Japanese" do
    m = memos(:one)
    title = "Note メモ"
    slug = Memo.derived_slug_from_title(title, m)
    if MemoMecabRomaji.romaji_slug_from(title).present?
      assert_equal "note-memo", slug
    else
      assert_equal "memo", slug
    end
  end

  test "global_slug_for appends uid suffix" do
    uid = ULID.generate.to_s
    assert_equal "hello-#{Memo.slug_suffix_for(uid)}", Memo.global_slug_for("hello", uid)
    assert_equal "hello-#{Memo.slug_suffix_for(uid)}", Memo.global_slug_for("hello-#{uid}", uid)
  end

  test "normalize_slug_fragment matches storage rules" do
    assert_equal "weird-slug", Memo.normalize_slug_fragment("  WEIRD SLUG!!  ")
    assert_nil Memo.normalize_slug_fragment("")
    assert_nil Memo.normalize_slug_fragment("   ")
  end

  test "slug syncs from title before file commit when not slug_manual" do
    m = Memo.new(
      body: "= Hi\n",
      title_manual: false,
      slug_manual: false,
      file_committed_at: nil,
      account: accounts(:one),
      memo_directory: memo_directories(:work)
    )
    m.save!
    assert_not m.slug_manual?
    assert_equal memo_global_slug("hi", m), m.slug
  end

  test "slug does not auto sync from title after file commit" do
    m = Memo.new(
      body: "= New title\n",
      title_manual: false,
      slug: "kept-slug",
      slug_manual: false,
      file_committed_at: Time.current,
      account: accounts(:one),
      memo_directory: memo_directories(:work)
    )
    m.save!
    assert_equal memo_global_slug("kept-slug", m), m.slug
  end

  test "display_as_draft? when never file-committed" do
    m = memos(:one)
    m.update_column(:file_committed_at, nil)
    assert m.reload.display_as_draft?
  end

  test "display_as_draft? is false when updated_at matches last file commit" do
    m = memos(:one)
    t = Time.zone.parse("2026-01-02 12:00:00")
    m.update_columns(file_committed_at: t, updated_at: t)
    assert_not m.reload.display_as_draft?
  end

  test "display_as_draft? when edited after file commit" do
    m = memos(:one)
    t = Time.zone.parse("2026-01-02 12:00:00")
    m.update_columns(file_committed_at: t, updated_at: t)
    m.touch
    assert m.reload.display_as_draft?
  end

  test "display_as_draft? is false for docs_sync read-only without file commit" do
    m = memos(:one)
    m.update!(
      file_committed_at: nil,
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/sample.adoc",
          "read_only" => true
        }
      }
    )
    assert_not m.display_as_draft?
  end

  test "display_as_draft? is false for docs_sync read-only after sync update" do
    m = memos(:one)
    t = 1.day.ago
    m.update!(
      file_committed_at: t,
      updated_at: Time.current,
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/sample.adoc",
          "read_only" => true
        }
      }
    )
    assert m.updated_at > m.file_committed_at
    assert_not m.display_as_draft?
  end

  test "group_read requires memo_group" do
    m = memos(:one)
    m.assign_attributes(visibility: :group_read, memo_group_id: nil)
    assert_not m.valid?
    assert m.errors[:memo_group_id].any?
  end

  test "group_read requires owner to belong to memo_group" do
    m = memos(:one)
    m.assign_attributes(visibility: :group_read, memo_group_id: memo_groups(:beta).id)
    assert_not m.valid?
  end

  test "group_read is valid when owner belongs to memo_group" do
    m = memos(:one)
    m.assign_attributes(visibility: :group_read, memo_group_id: memo_groups(:alpha).id)
    assert m.valid?
  end

  test "assigns a ULID uid on create when none given" do
    m = Memo.create!(body: "= Auto uid", account: accounts(:one), memo_directory: memo_directories(:work))
    assert_match Memo::UID_FORMAT, m.uid
  end

  test "respects and upcases a client-provided uid" do
    client_uid = ULID.generate.to_s.downcase
    m = Memo.create!(uid: client_uid, body: "= Client uid", account: accounts(:one), memo_directory: memo_directories(:work))
    assert_equal client_uid.upcase, m.uid
  end

  test "uid must be unique" do
    m = Memo.new(uid: memos(:one).uid, body: "= Dup", account: accounts(:one), memo_directory: memo_directories(:work))
    assert_not m.valid?
    assert m.errors[:uid].any?
  end

  test "rejects malformed uid" do
    m = Memo.new(body: "= Bad", account: accounts(:one), memo_directory: memo_directories(:work))
    m.uid = "not-a-valid-ulid"
    assert_not m.valid?
    assert m.errors[:uid].any?
  end

  test "slug_stem strips a trailing numeric id" do
    assert_equal "first-memo", Memo.slug_stem("first-memo-42")
  end

  test "slug_stem strips a trailing ULID suffix" do
    ulid = ULID.generate.to_s.downcase
    assert_equal "first-memo", Memo.slug_stem("first-memo-#{ulid}")
  end

  test "slug_stem keeps stem when there is no id-like suffix" do
    assert_equal "plain-note", Memo.slug_stem("plain-note")
  end

  test "slug_stem strips explicit memo_id even when not purely numeric tail" do
    assert_equal "note", Memo.slug_stem("note-7", memo_id: 7)
  end

  test "global_slug_for replaces legacy suffix with uid suffix" do
    uid = ULID.generate.to_s
    legacy = ULID.generate.to_s
    assert_equal "note-#{Memo.slug_suffix_for(uid)}", Memo.global_slug_for("note-#{legacy}", uid)
  end

  test "media_album_id reads and writes ULID in properties" do
    memo = memos(:one)
    ulid = ULID.generate.to_s
    memo.media_album_id = ulid
    assert_equal ulid.upcase, memo.properties["media_album_id"]
    assert_equal ulid.upcase, memo.media_album_id

    memo.media_album_id = nil
    assert_nil memo.media_album_id
    assert_not memo.properties.key?("media_album_id")
  end

  test "scheduled_on reads and writes ISO8601 date in properties" do
    memo = memos(:one)
    memo.scheduled_on = Date.new(2026, 5, 15)
    assert_equal "2026-05-15", memo.properties["scheduled_on"]
    assert_equal Date.new(2026, 5, 15), memo.scheduled_on

    memo.scheduled_on = nil
    assert_nil memo.scheduled_on
    assert_not memo.properties.key?("scheduled_on")
  end
end
