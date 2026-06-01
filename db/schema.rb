# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_01_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_login_change_keys", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
    t.string "login", null: false
  end

  create_table "account_password_reset_keys", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "key", null: false
  end

  create_table "account_remember_keys", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
  end

  create_table "account_verification_keys", force: :cascade do |t|
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "key", null: false
    t.datetime "requested_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "accounts", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "clip_api_token_created_at"
    t.string "clip_api_token_digest"
    t.string "clip_api_token_prefix"
    t.string "email", null: false
    t.json "google_calendar_meta", default: {}, null: false
    t.text "google_calendar_refresh_token"
    t.string "nickname"
    t.text "openai_api_key"
    t.string "password_hash"
    t.integer "status", default: 1, null: false
    t.json "theme_preference", default: {}, null: false
    t.datetime "tsuzura_api_token_created_at"
    t.string "tsuzura_api_token_digest"
    t.string "tsuzura_api_token_prefix"
    t.index ["clip_api_token_digest"], name: "index_accounts_on_clip_api_token_digest", unique: true
    t.index ["email"], name: "index_accounts_on_email", unique: true, where: "(status = ANY (ARRAY[1, 2]))"
    t.index ["tsuzura_api_token_digest"], name: "index_accounts_on_tsuzura_api_token_digest", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "board_columns", force: :cascade do |t|
    t.integer "board_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["board_id", "position"], name: "index_board_columns_on_board_id_and_position", unique: true
    t.index ["board_id"], name: "index_board_columns_on_board_id"
  end

  create_table "boards", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.integer "memo_directory_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_boards_on_account_id"
    t.index ["memo_directory_id"], name: "index_boards_on_memo_directory_id"
  end

  create_table "memo_directories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "full_path", null: false
    t.string "label", default: "", null: false
    t.integer "parent_id"
    t.string "path_segment", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["full_path"], name: "index_memo_directories_on_full_path", unique: true
    t.index ["parent_id"], name: "index_memo_directories_on_parent_id"
  end

  create_table "memo_group_memberships", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.integer "memo_group_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_memo_group_memberships_on_account_id"
    t.index ["memo_group_id", "account_id"], name: "index_memo_group_memberships_on_memo_group_id_and_account_id", unique: true
    t.index ["memo_group_id"], name: "index_memo_group_memberships_on_memo_group_id"
  end

  create_table "memo_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "memo_tags", force: :cascade do |t|
    t.integer "memo_id", null: false
    t.integer "tag_id", null: false
    t.index ["memo_id", "tag_id"], name: "index_memo_tags_on_memo_id_and_tag_id", unique: true
    t.index ["memo_id"], name: "index_memo_tags_on_memo_id"
    t.index ["tag_id"], name: "index_memo_tags_on_tag_id"
  end

  create_table "memo_view_histories", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.integer "memo_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "view_sequence", null: false
    t.datetime "viewed_at", null: false
    t.index ["account_id", "memo_id"], name: "index_memo_view_histories_on_account_id_and_memo_id", unique: true
    t.index ["account_id", "view_sequence"], name: "index_memo_view_histories_on_account_id_and_view_sequence", order: { view_sequence: :desc }
    t.index ["account_id", "viewed_at"], name: "index_memo_view_histories_on_account_id_and_viewed_at"
    t.index ["account_id"], name: "index_memo_view_histories_on_account_id"
    t.index ["memo_id"], name: "index_memo_view_histories_on_memo_id"
  end

  create_table "memo_wiki_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "source_memo_id", null: false
    t.integer "target_memo_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source_memo_id", "target_memo_id"], name: "index_memo_wiki_links_on_source_memo_id_and_target_memo_id", unique: true
    t.index ["source_memo_id"], name: "index_memo_wiki_links_on_source_memo_id"
    t.index ["target_memo_id"], name: "index_memo_wiki_links_on_target_memo_id"
  end

  create_table "memos", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "board_id"
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "file_committed_at"
    t.integer "kanban_column_id"
    t.integer "kanban_position", default: 0, null: false
    t.integer "memo_directory_id", null: false
    t.integer "memo_group_id"
    t.jsonb "properties", default: {}, null: false
    t.string "slug"
    t.boolean "slug_manual", default: false, null: false
    t.string "title", null: false
    t.boolean "title_manual", default: false, null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "visibility", default: 4, null: false
    t.index ["account_id"], name: "index_memos_on_account_id"
    t.index ["board_id"], name: "index_memos_on_board_id"
    t.index ["kanban_column_id"], name: "index_memos_on_kanban_column_id"
    t.index ["memo_directory_id"], name: "index_memos_on_memo_directory_id"
    t.index ["memo_group_id"], name: "index_memos_on_memo_group_id"
    t.index ["slug"], name: "index_memos_on_slug", unique: true
    t.index ["uid"], name: "index_memos_on_uid", unique: true
  end

  create_table "notebook_memos", force: :cascade do |t|
    t.string "chapter_title"
    t.datetime "created_at", null: false
    t.integer "memo_id", null: false
    t.integer "notebook_id", null: false
    t.integer "parent_id"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["memo_id"], name: "index_notebook_memos_on_memo_id"
    t.index ["notebook_id", "memo_id"], name: "index_notebook_memos_on_notebook_id_and_memo_id", unique: true
    t.index ["notebook_id", "parent_id", "position"], name: "index_notebook_memos_on_notebook_parent_position"
    t.index ["notebook_id"], name: "index_notebook_memos_on_notebook_id"
    t.index ["parent_id"], name: "index_notebook_memos_on_parent_id"
  end

  create_table "notebooks", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description", default: "", null: false
    t.integer "memo_directory_id"
    t.integer "publication_kind", default: 2, null: false
    t.datetime "published_at"
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "publication_kind"], name: "index_notebooks_on_account_id_and_publication_kind"
    t.index ["account_id", "slug"], name: "index_notebooks_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_notebooks_on_account_id"
    t.index ["memo_directory_id"], name: "index_notebooks_on_memo_directory_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_name"], name: "index_tags_on_normalized_name", unique: true
  end

  create_table "tsuzura_album_items", force: :cascade do |t|
    t.string "album_id", limit: 26, null: false
    t.datetime "created_at", null: false
    t.string "media_item_id", limit: 26, null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["album_id", "media_item_id"], name: "index_tsuzura_album_items_on_album_id_and_media_item_id", unique: true
    t.index ["album_id", "position"], name: "index_tsuzura_album_items_on_album_id_and_position"
  end

  create_table "tsuzura_albums", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.string "cover_media_id", limit: 26
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "owner_account_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["cover_media_id"], name: "index_tsuzura_albums_on_cover_media_id"
    t.index ["owner_account_id"], name: "index_tsuzura_albums_on_owner_account_id"
  end

  create_table "tsuzura_media_items", id: { type: :string, limit: 26 }, force: :cascade do |t|
    t.datetime "captured_at"
    t.string "checksum"
    t.datetime "created_at", null: false
    t.jsonb "exif", default: {}, null: false
    t.integer "height"
    t.string "kind", default: "image", null: false
    t.string "original_filename"
    t.bigint "owner_account_id", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["checksum"], name: "index_tsuzura_media_items_on_checksum"
    t.index ["owner_account_id"], name: "index_tsuzura_media_items_on_owner_account_id"
  end

  add_foreign_key "account_login_change_keys", "accounts", column: "id"
  add_foreign_key "account_password_reset_keys", "accounts", column: "id"
  add_foreign_key "account_remember_keys", "accounts", column: "id"
  add_foreign_key "account_verification_keys", "accounts", column: "id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "board_columns", "boards"
  add_foreign_key "boards", "accounts"
  add_foreign_key "boards", "memo_directories"
  add_foreign_key "memo_directories", "memo_directories", column: "parent_id"
  add_foreign_key "memo_group_memberships", "accounts"
  add_foreign_key "memo_group_memberships", "memo_groups"
  add_foreign_key "memo_tags", "memos"
  add_foreign_key "memo_tags", "tags"
  add_foreign_key "memo_view_histories", "accounts"
  add_foreign_key "memo_view_histories", "memos"
  add_foreign_key "memo_wiki_links", "memos", column: "source_memo_id", on_delete: :cascade
  add_foreign_key "memo_wiki_links", "memos", column: "target_memo_id", on_delete: :cascade
  add_foreign_key "memos", "accounts"
  add_foreign_key "memos", "board_columns", column: "kanban_column_id"
  add_foreign_key "memos", "boards"
  add_foreign_key "memos", "memo_directories"
  add_foreign_key "memos", "memo_groups"
  add_foreign_key "notebook_memos", "memos"
  add_foreign_key "notebook_memos", "notebook_memos", column: "parent_id"
  add_foreign_key "notebook_memos", "notebooks"
  add_foreign_key "notebooks", "accounts"
  add_foreign_key "notebooks", "memo_directories"
  add_foreign_key "tsuzura_album_items", "tsuzura_albums", column: "album_id"
  add_foreign_key "tsuzura_album_items", "tsuzura_media_items", column: "media_item_id"
end
