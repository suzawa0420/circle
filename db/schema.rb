# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_09_25_120000) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "account_blocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ip_address"
    t.integer "block", default: 0, null: false
    t.string "model"
    t.string "url"
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "gender"
    t.string "nickname"
    t.string "image_profile"
    t.text "profile"
    t.integer "check"
    t.bigint "prefecture_id"
    t.string "age"
    t.integer "open", default: 0, null: false
    t.boolean "moderator", default: false, null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["prefecture_id"], name: "index_admin_users_on_prefecture_id"
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "ages", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "decade"
  end

  create_table "applications", force: :cascade do |t|
    t.bigint "member_id", null: false
    t.datetime "applied_at", null: false
    t.string "status", default: "pending"
    t.datetime "won_at"
    t.integer "points_used", default: 30, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["member_id"], name: "index_applications_on_member_id"
  end

  create_table "blogs", force: :cascade do |t|
    t.string "title"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "content"
    t.string "image_01"
    t.string "image_02"
    t.string "image_03"
    t.string "image_04"
    t.string "blog_image_name"
    t.string "photo_file_name"
    t.string "photo_content_type"
    t.string "photo_file_size"
    t.string "photo_updated_at"
    t.string "photo"
    t.integer "impressions_count", default: 0
    t.index ["user_id"], name: "index_blogs_on_user_id"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.bigint "member_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id"], name: "index_bookmarks_on_member_id"
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.string "kana"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "order"
    t.string "txt"
  end

  create_table "cities", force: :cascade do |t|
    t.string "prefecture_id"
    t.string "city_kana"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.integer "places_count", default: 0, null: false
  end

  create_table "collections", force: :cascade do |t|
    t.string "day"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "price"
    t.index ["user_id"], name: "index_collections_on_user_id"
  end

  create_table "columns", force: :cascade do |t|
    t.string "title"
    t.text "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.string "image"
  end

  create_table "db_keywords", force: :cascade do |t|
    t.string "keyword"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "search_count", default: 0, null: false
  end

  create_table "db_searches", force: :cascade do |t|
    t.string "keyword"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "db_validation_errors", force: :cascade do |t|
    t.string "name"
    t.text "content_01"
    t.text "content_02"
    t.text "content_03"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "differences", force: :cascade do |t|
    t.string "letter"
    t.string "dummy"
    t.string "order"
    t.text "combine"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "event_answers", force: :cascade do |t|
    t.text "answer"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "event_question_id"
    t.bigint "member_id"
    t.string "answer_member_id"
    t.string "nickname"
    t.string "icon"
    t.index ["event_question_id"], name: "index_event_answers_on_event_question_id"
    t.index ["member_id"], name: "index_event_answers_on_member_id"
  end

  create_table "event_questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "question"
    t.bigint "event_id"
    t.index ["event_id"], name: "index_event_questions_on_event_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ruby"
    t.string "icon"
    t.string "order"
    t.string "category"
    t.string "openchat"
    t.string "txt"
    t.integer "matching"
    t.integer "place"
    t.string "category_id"
    t.integer "users_count", default: 0, null: false
  end

  create_table "exhibition_categories", force: :cascade do |t|
    t.string "name"
    t.string "display_name"
    t.string "kana"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "exhibition_contacts", force: :cascade do |t|
    t.bigint "exhibition_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.integer "subject"
    t.text "content", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["exhibition_id"], name: "index_exhibition_contacts_on_exhibition_id"
  end

  create_table "exhibition_group_profiles", force: :cascade do |t|
    t.bigint "exhibition_group_id", null: false
    t.bigint "exhibition_category_id", null: false
    t.string "name", null: false
    t.string "header_img"
    t.string "profile_img"
    t.string "instagram_id"
    t.string "twitter_id"
    t.string "web_url"
    t.text "introduction"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["exhibition_category_id"], name: "index_exhibition_group_profiles_on_exhibition_category_id"
    t.index ["exhibition_group_id"], name: "index_exhibition_group_profiles_on_exhibition_group_id"
  end

  create_table "exhibition_groups", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["email"], name: "index_exhibition_groups_on_email", unique: true
    t.index ["reset_password_token"], name: "index_exhibition_groups_on_reset_password_token", unique: true
  end

  create_table "exhibitions", force: :cascade do |t|
    t.bigint "exhibition_group_id", null: false
    t.bigint "prefecture_id", null: false
    t.string "name", null: false
    t.datetime "event_date"
    t.datetime "end_date"
    t.string "header_img"
    t.string "gallery_img_01"
    t.string "gallery_img_02"
    t.string "gallery_img_03"
    t.string "gallery_img_04"
    t.string "venue_name"
    t.string "venue_address"
    t.text "detail"
    t.integer "online", default: 1
    t.integer "show_contact", default: 1
    t.integer "exhibit_person_price"
    t.integer "visitor_price"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["exhibition_group_id"], name: "index_exhibitions_on_exhibition_group_id"
    t.index ["prefecture_id"], name: "index_exhibitions_on_prefecture_id"
  end

  create_table "groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.string "group"
  end

  create_table "impressions", force: :cascade do |t|
    t.string "impressionable_type"
    t.integer "impressionable_id"
    t.integer "user_id"
    t.string "controller_name"
    t.string "action_name"
    t.string "view_name"
    t.string "request_hash"
    t.string "ip_address"
    t.string "session_hash"
    t.text "message"
    t.text "referrer"
    t.text "params"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["controller_name", "action_name", "ip_address"], name: "controlleraction_ip_index"
    t.index ["controller_name", "action_name", "request_hash"], name: "controlleraction_request_index"
    t.index ["controller_name", "action_name", "session_hash"], name: "controlleraction_session_index"
    t.index ["impressionable_type", "impressionable_id", "ip_address"], name: "poly_ip_index"
    t.index ["impressionable_type", "impressionable_id", "params"], name: "poly_params_request_index"
    t.index ["impressionable_type", "impressionable_id", "request_hash"], name: "poly_request_index"
    t.index ["impressionable_type", "impressionable_id", "session_hash"], name: "poly_session_index"
    t.index ["impressionable_type", "message", "impressionable_id"], name: "impressionable_type_message_index"
    t.index ["user_id"], name: "index_impressions_on_user_id"
  end

  create_table "invalid_emails", force: :cascade do |t|
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "items", force: :cascade do |t|
    t.bigint "collection_id"
    t.string "name"
    t.integer "money"
    t.string "check"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id"], name: "index_items_on_collection_id"
  end

  create_table "likes", force: :cascade do |t|
    t.integer "user_id"
    t.integer "blog_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blog_id"], name: "index_likes_on_blog_id"
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "unique_id"
    t.string "link01_title"
    t.string "link01_url"
    t.string "link02_title"
    t.string "link02_url"
    t.string "link03_title"
    t.string "link03_url"
    t.string "link04_title"
    t.string "link04_url"
    t.string "link05_title"
    t.string "link05_url"
    t.index ["unique_id"], name: "index_links_on_unique_id", unique: true
    t.index ["user_id"], name: "index_links_on_user_id"
  end

  create_table "matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "age_group"
    t.string "member"
    t.string "level"
    t.string "recruit"
    t.text "comment"
    t.bigint "user_id"
    t.index ["user_id"], name: "index_matches_on_user_id"
  end

  create_table "members", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "nickname"
    t.string "image_profile"
    t.string "random_id"
    t.string "gender"
    t.text "profile"
    t.bigint "prefecture_id"
    t.string "age"
    t.integer "points", default: 0, null: false
    t.datetime "last_get_point_at"
    t.integer "living_prefecture_id", comment: "現住所: 都道府県"
    t.string "living_city", comment: "現住所: 市区町村"
    t.string "living_address", comment: "現住所: 以下住所"
    t.index ["email"], name: "index_members_on_email", unique: true
    t.index ["prefecture_id"], name: "index_members_on_prefecture_id"
    t.index ["reset_password_token"], name: "index_members_on_reset_password_token", unique: true
  end

  create_table "members_events", force: :cascade do |t|
    t.bigint "member_id"
    t.bigint "event_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_members_events_on_event_id"
    t.index ["member_id"], name: "index_members_events_on_member_id"
  end

  create_table "name_schedules", force: :cascade do |t|
    t.bigint "name_id"
    t.bigint "schedule_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "answer"
    t.string "comment"
    t.index ["name_id"], name: "index_name_schedules_on_name_id"
    t.index ["schedule_id"], name: "index_name_schedules_on_schedule_id"
  end

  create_table "names", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "gender"
  end

  create_table "opinions", force: :cascade do |t|
    t.text "opinion"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_opinions_on_user_id"
  end

  create_table "place_reviews", force: :cascade do |t|
    t.integer "event_id"
    t.string "ip_address"
    t.text "comment"
    t.bigint "place_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "average_score"
    t.float "facility"
    t.float "reservation"
    t.float "price"
    t.float "access"
    t.index ["place_id"], name: "index_place_reviews_on_place_id"
  end

  create_table "places", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "prefecture_id"
    t.integer "city_id"
    t.integer "event_id"
    t.string "name"
    t.string "address"
    t.string "access"
    t.string "tag"
    t.string "parking"
    t.string "time"
    t.string "regular_holiday"
    t.string "scale"
    t.string "price"
    t.string "tel"
    t.string "url"
    t.text "sns"
    t.string "img_link"
    t.string "img_url"
    t.string "img_source"
    t.float "average_facility"
    t.float "average_reservation"
    t.float "average_price"
    t.float "average_access"
    t.float "average_score"
  end

  create_table "places_events", force: :cascade do |t|
    t.bigint "place_id"
    t.bigint "event_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_places_events_on_event_id"
    t.index ["place_id"], name: "index_places_events_on_place_id"
  end

  create_table "prefectures", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kana"
    t.string "group"
    t.string "order"
    t.integer "sort"
    t.integer "places_count", default: 0, null: false
  end

  create_table "questions", force: :cascade do |t|
    t.text "content"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "answer"
    t.string "ip_address"
    t.index ["user_id"], name: "index_questions_on_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "member_id"
    t.text "comment"
    t.integer "review"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ip"
    t.string "age"
    t.string "gender"
    t.string "nickname"
    t.index ["member_id"], name: "index_reviews_on_member_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "schedules", force: :cascade do |t|
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "day"
    t.string "venue"
    t.string "date"
    t.time "time_s"
    t.time "time_e"
    t.string "venue_address"
    t.text "note"
    t.string "title"
    t.string "google_map"
    t.string "recruitment"
    t.string "member_venue"
    t.integer "recruitment_numbers"
    t.string "cost"
    t.string "top_image"
    t.index ["user_id"], name: "index_schedules_on_user_id"
  end

  create_table "stations", force: :cascade do |t|
    t.string "city_id"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tags", force: :cascade do |t|
    t.string "category"
    t.string "tag"
    t.string "name"
    t.string "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "order"
  end

  create_table "user_contacts", force: :cascade do |t|
    t.bigint "user_id"
    t.string "mail"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "entry"
    t.string "respond_check"
    t.string "random_id"
    t.string "name"
    t.string "ip_address"
    t.string "account_block"
    t.string "contact_del"
    t.text "comment"
    t.text "violation"
    t.index ["user_id"], name: "index_user_contacts_on_user_id"
  end

  create_table "user_tags", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "tag_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_user_tags_on_tag_id"
    t.index ["user_id"], name: "index_user_tags_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_name"
    t.string "line_id"
    t.string "switch"
    t.string "item"
    t.string "prefecture"
    t.string "area"
    t.string "schedule"
    t.string "age"
    t.string "recruitment"
    t.string "foundation"
    t.string "member"
    t.string "average_age"
    t.string "cost"
    t.string "web"
    t.text "appeal"
    t.string "password"
    t.string "goal"
    t.bigint "prefecture_id"
    t.string "user_id"
    t.integer "event_id"
    t.integer "decade_age"
    t.string "header_image"
    t.string "pic_profile"
    t.string "pic_header"
    t.string "last_post"
    t.string "grouping"
    t.string "gallery_01"
    t.string "gallery_02"
    t.string "gallery_03"
    t.string "gallery_04"
    t.text "requirement"
    t.integer "impressions_count", default: 0
    t.integer "line_count", default: 0
    t.integer "mail_count", default: 0
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.bigint "admin_user_id"
    t.string "user_time"
    t.string "contact"
    t.string "twitter"
    t.string "instagram"
    t.integer "prefecture_sub_id"
    t.text "template"
    t.integer "sent_count"
    t.string "review_score"
    t.string "ng_account"
    t.string "category_id"
    t.string "unique_id"
    t.string "point"
    t.float "cb_point", default: 0.0, null: false
    t.boolean "review_permit", default: true
    t.index ["admin_user_id"], name: "index_users_on_admin_user_id"
    t.index ["event_id"], name: "index_users_on_event_id"
    t.index ["last_post"], name: "index_users_on_last_post"
    t.index ["ng_account"], name: "index_users_on_ng_account"
    t.index ["prefecture_id"], name: "index_users_on_prefecture_id"
    t.index ["prefecture_sub_id"], name: "index_users_on_prefecture_sub_id"
    t.index ["switch"], name: "index_users_on_switch"
    t.index ["switch", "created_at"], name: "index_users_on_switch_and_created_at_desc", order: { created_at: :desc }
    t.index ["switch", "last_post"], name: "index_users_on_switch_and_last_post_desc", order: { last_post: :desc }
    t.index ["switch", "cb_point", "last_post"], name: "index_users_on_switch_popularity_and_last_post", order: { cb_point: :desc, last_post: :desc }
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "users_ages", force: :cascade do |t|
    t.integer "user_id"
    t.integer "age_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["age_id"], name: "index_users_ages_on_age_id"
    t.index ["user_id"], name: "index_users_ages_on_user_id"
  end

  create_table "users_cities", force: :cascade do |t|
    t.integer "user_id"
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["city_id"], name: "index_users_cities_on_city_id"
    t.index ["user_id"], name: "index_users_cities_on_user_id"
  end

  create_table "users_groups", force: :cascade do |t|
    t.integer "user_id"
    t.integer "group_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id"], name: "index_users_groups_on_group_id"
    t.index ["user_id"], name: "index_users_groups_on_user_id"
  end

  add_foreign_key "applications", "members"
  add_foreign_key "blogs", "users"
  add_foreign_key "bookmarks", "members"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "collections", "users"
  add_foreign_key "exhibition_contacts", "exhibitions"
  add_foreign_key "exhibition_group_profiles", "exhibition_categories"
  add_foreign_key "exhibition_group_profiles", "exhibition_groups"
  add_foreign_key "exhibitions", "exhibition_groups"
  add_foreign_key "exhibitions", "prefectures"
  add_foreign_key "items", "collections"
  add_foreign_key "links", "users"
  add_foreign_key "matches", "users"
  add_foreign_key "members_events", "events"
  add_foreign_key "members_events", "members"
  add_foreign_key "name_schedules", "names"
  add_foreign_key "name_schedules", "schedules"
  add_foreign_key "place_reviews", "places"
  add_foreign_key "places_events", "events"
  add_foreign_key "places_events", "places"
  add_foreign_key "questions", "users"
  add_foreign_key "reviews", "members"
  add_foreign_key "reviews", "users"
  add_foreign_key "schedules", "users"
  add_foreign_key "user_contacts", "users"
  add_foreign_key "user_tags", "tags"
  add_foreign_key "user_tags", "users"
  add_foreign_key "users", "prefectures"
end
