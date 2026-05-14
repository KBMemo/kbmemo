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

ActiveRecord::Schema[8.1].define(version: 2026_05_15_004900) do
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
    t.string "email", null: false
    t.string "nickname"
    t.string "password_hash"
    t.integer "status", default: 1, null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true, where: "status IN (1, 2)"
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

  create_table "memos", force: :cascade do |t|
    t.integer "account_id", null: false
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "file_committed_at"
    t.integer "memo_directory_id", null: false
    t.integer "memo_group_id"
    t.json "properties", default: {}, null: false
    t.string "slug"
    t.boolean "slug_manual", default: false, null: false
    t.string "title", null: false
    t.boolean "title_manual", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "visibility", default: 0, null: false
    t.index ["account_id"], name: "index_memos_on_account_id"
    t.index ["memo_directory_id", "slug"], name: "index_memos_on_memo_directory_id_and_slug", unique: true
    t.index ["memo_directory_id"], name: "index_memos_on_memo_directory_id"
    t.index ["memo_group_id"], name: "index_memos_on_memo_group_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_name"], name: "index_tags_on_normalized_name", unique: true
  end

  add_foreign_key "account_login_change_keys", "accounts", column: "id"
  add_foreign_key "account_password_reset_keys", "accounts", column: "id"
  add_foreign_key "account_remember_keys", "accounts", column: "id"
  add_foreign_key "account_verification_keys", "accounts", column: "id"
  add_foreign_key "memo_directories", "memo_directories", column: "parent_id"
  add_foreign_key "memo_group_memberships", "accounts"
  add_foreign_key "memo_group_memberships", "memo_groups"
  add_foreign_key "memo_tags", "memos"
  add_foreign_key "memo_tags", "tags"
  add_foreign_key "memos", "accounts"
  add_foreign_key "memos", "memo_directories"
  add_foreign_key "memos", "memo_groups"
end
