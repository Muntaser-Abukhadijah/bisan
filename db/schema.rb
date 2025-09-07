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

ActiveRecord::Schema[8.0].define(version: 2025_09_07_111419) do
  create_table "articles", force: :cascade do |t|
    t.string "title"
    t.string "article_image"
    t.text "excerpt"
    t.string "category"
    t.date "publish_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body"
    t.string "source_url"
    t.string "tags"
    t.integer "author_id", null: false
    t.string "source_id"
    t.datetime "ingested_at"
    t.string "content_hash"
    t.index ["author_id"], name: "index_articles_on_author_id"
    t.index ["content_hash"], name: "index_articles_on_content_hash"
    t.index ["source_id"], name: "index_articles_on_source_id"
    t.index ["source_url"], name: "idx_articles_source_url_unique", unique: true, where: "source_url IS NOT NULL"
    t.index ["source_url"], name: "index_articles_on_source_url", unique: true
  end

  create_table "authors", force: :cascade do |t|
    t.string "name", null: false
    t.text "bio"
    t.string "avatar_url"
    t.json "social_links", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "articles_count", default: 0, null: false
    t.index ["articles_count"], name: "index_authors_on_articles_count"
  end

  add_foreign_key "articles", "authors"
end
