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

ActiveRecord::Schema[8.1].define(version: 2026_05_13_120000) do
  create_table "memo_directories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", default: "", null: false
    t.string "path_segment", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["path_segment"], name: "index_memo_directories_on_path_segment", unique: true
  end

  create_table "memo_tags", force: :cascade do |t|
    t.integer "memo_id", null: false
    t.integer "tag_id", null: false
    t.index ["memo_id", "tag_id"], name: "index_memo_tags_on_memo_id_and_tag_id", unique: true
    t.index ["memo_id"], name: "index_memo_tags_on_memo_id"
    t.index ["tag_id"], name: "index_memo_tags_on_tag_id"
  end

  create_table "memos", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "file_committed_at"
    t.integer "memo_directory_id", null: false
    t.json "properties", default: {}, null: false
    t.string "slug"
    t.boolean "slug_manual", default: false, null: false
    t.string "title", null: false
    t.boolean "title_manual", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["memo_directory_id", "slug"], name: "index_memos_on_memo_directory_id_and_slug", unique: true
    t.index ["memo_directory_id"], name: "index_memos_on_memo_directory_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_name"], name: "index_tags_on_normalized_name", unique: true
  end

  add_foreign_key "memo_tags", "memos"
  add_foreign_key "memo_tags", "tags"
  add_foreign_key "memos", "memo_directories"
end
