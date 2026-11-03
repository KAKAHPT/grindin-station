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

ActiveRecord::Schema[8.1].define(version: 2026_11_04_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "postgis"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
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

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "circuit_standings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "circuit_id", null: false
    t.datetime "created_at", null: false
    t.integer "events_count", default: 0, null: false
    t.uuid "player_id", null: false
    t.decimal "points", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["circuit_id", "player_id"], name: "index_circuit_standings_on_circuit_id_and_player_id", unique: true
    t.index ["circuit_id"], name: "index_circuit_standings_on_circuit_id"
    t.index ["player_id"], name: "index_circuit_standings_on_player_id"
  end

  create_table "circuits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.uuid "event_organizer_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["event_organizer_id"], name: "index_circuits_on_event_organizer_id"
  end

  create_table "event_organizers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "default_currency", default: 0
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["user_id"], name: "index_event_organizers_on_user_id"
  end

  create_table "event_participants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "checked_in", default: false, null: false
    t.datetime "checked_in_at"
    t.datetime "created_at", null: false
    t.string "decklist"
    t.string "drop_reason"
    t.boolean "dropped", default: false
    t.datetime "dropped_at"
    t.uuid "event_id"
    t.integer "final_position"
    t.integer "fixed_pod"
    t.decimal "league_score", precision: 10, scale: 2, default: "1000.0"
    t.boolean "paid", default: false, null: false
    t.uuid "player_id"
    t.datetime "updated_at", null: false
    t.integer "waitlist_position"
    t.boolean "waitlisted", default: false, null: false
    t.index ["event_id"], name: "index_event_participants_on_event_id"
    t.index ["player_id"], name: "index_event_participants_on_player_id"
  end

  create_table "event_staff", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "event_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["event_id", "user_id"], name: "index_event_staff_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_event_staff_on_event_id"
    t.index ["user_id"], name: "index_event_staff_on_user_id"
  end

  create_table "events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "address"
    t.uuid "circuit_id"
    t.integer "confirmation_timeout_minutes", default: 5, null: false
    t.datetime "created_at", null: false
    t.integer "currency"
    t.text "description"
    t.datetime "end_time"
    t.uuid "event_organizer_id"
    t.integer "event_participants_count", default: 0, null: false
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.string "name", null: false
    t.int4range "participants_range"
    t.integer "play_mode", default: 0, null: false
    t.integer "points_bye", default: 7, null: false
    t.integer "points_draw", default: 1, null: false
    t.integer "points_loss", default: 0, null: false
    t.integer "points_win", default: 7, null: false
    t.decimal "price"
    t.text "prizes"
    t.string "result_confirmation", default: "none", null: false
    t.integer "round_minutes", default: 80, null: false
    t.integer "rounds_count", default: 0, null: false
    t.text "rules"
    t.text "schedule"
    t.integer "seed"
    t.boolean "self_report_enabled", default: true, null: false
    t.boolean "show_commanders_in_standings", default: false, null: false
    t.string "slug", null: false
    t.datetime "start_time"
    t.integer "state", default: 0, null: false
    t.integer "swiss_rounds_count"
    t.integer "top_cut_round_minutes", default: 150, null: false
    t.integer "top_cut_size"
    t.string "top_cut_timeout_rule", default: "highest_seed_advances", null: false
    t.string "type", default: "Tournament", null: false
    t.datetime "updated_at", null: false
    t.decimal "wager_percentage", precision: 5, scale: 2
    t.boolean "waitlist_enabled", default: false, null: false
    t.index ["circuit_id"], name: "index_events_on_circuit_id"
    t.index ["event_organizer_id"], name: "index_events_on_event_organizer_id"
    t.index ["location"], name: "index_events_on_location", using: :gist
  end

  create_table "identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "infractions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "category", default: 205, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.uuid "event_id"
    t.integer "kind", default: 200, null: false
    t.integer "penalty", default: 0, null: false
    t.uuid "player_id"
    t.uuid "pod_id"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_infractions_on_event_id"
    t.index ["player_id"], name: "index_infractions_on_player_id"
    t.index ["pod_id"], name: "index_infractions_on_pod_id"
  end

  create_table "judge_calls", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.uuid "acknowledged_by_user_id"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.uuid "event_id", null: false
    t.uuid "event_participant_id"
    t.uuid "pod_id"
    t.text "reason"
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "status"], name: "index_judge_calls_on_event_id_and_status"
    t.index ["pod_id"], name: "index_judge_calls_on_pod_id"
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.datetime "read_at"
    t.uuid "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["subject_type", "subject_id"], name: "index_notifications_on_subject"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
  end

  create_table "players", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["key"], name: "index_players_on_key"
    t.index ["user_id"], name: "index_players_on_user_id"
  end

  create_table "pods", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "confirmations", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "disputed", default: false, null: false
    t.integer "extra_time", default: 0, null: false
    t.integer "number", null: false
    t.jsonb "pending_result"
    t.datetime "reported_at"
    t.uuid "reported_by_participant_id"
    t.datetime "review_requested_at"
    t.uuid "round_id"
    t.integer "size", default: 4
    t.datetime "updated_at", null: false
    t.index ["number", "round_id"], name: "index_pods_on_number_and_round_id", unique: true
    t.index ["round_id"], name: "index_pods_on_round_id"
  end

  create_table "results", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "event_participant_id"
    t.uuid "recorded_by_user_id"
    t.uuid "round_id"
    t.uuid "superseded_by_id"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["event_participant_id", "round_id"], name: "index_results_current_on_participant_and_round", unique: true, where: "(superseded_by_id IS NULL)"
    t.index ["event_participant_id"], name: "index_results_on_event_participant_id"
    t.index ["recorded_by_user_id"], name: "index_results_on_recorded_by_user_id"
    t.index ["round_id"], name: "index_results_on_round_id"
    t.index ["superseded_by_id"], name: "index_results_on_superseded_by_id"
  end

  create_table "rooms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "event_id"
    t.text "name"
    t.int4range "pod_range"
    t.integer "pods_per_row"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_rooms_on_event_id"
  end

  create_table "rounds", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "event_id"
    t.datetime "finished_at"
    t.boolean "is_finals_round", default: false, null: false
    t.boolean "is_play_round", default: false, null: false
    t.integer "number", default: 1, null: false
    t.boolean "published", default: false, null: false
    t.datetime "started_at"
    t.string "type", default: "SwissRound"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_rounds_on_event_id"
  end

  create_table "seatings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "assigned_by", default: "fair", null: false
    t.integer "cost"
    t.datetime "created_at", null: false
    t.uuid "event_participant_id"
    t.integer "order", default: 1, null: false
    t.uuid "pod_id"
    t.datetime "updated_at", null: false
    t.index ["event_participant_id"], name: "index_seatings_on_event_participant_id"
    t.index ["pod_id"], name: "index_seatings_on_pod_id"
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "circuit_standings", "circuits"
  add_foreign_key "circuit_standings", "players"
  add_foreign_key "circuits", "event_organizers"
  add_foreign_key "event_organizers", "users"
  add_foreign_key "event_participants", "events"
  add_foreign_key "event_participants", "players"
  add_foreign_key "event_staff", "events"
  add_foreign_key "event_staff", "users"
  add_foreign_key "events", "circuits"
  add_foreign_key "identities", "users"
  add_foreign_key "infractions", "events"
  add_foreign_key "infractions", "players"
  add_foreign_key "infractions", "pods"
  add_foreign_key "judge_calls", "event_participants", on_delete: :nullify
  add_foreign_key "judge_calls", "events"
  add_foreign_key "judge_calls", "pods", on_delete: :nullify
  add_foreign_key "judge_calls", "users", column: "acknowledged_by_user_id", on_delete: :nullify
  add_foreign_key "notifications", "users"
  add_foreign_key "players", "users"
  add_foreign_key "pods", "event_participants", column: "reported_by_participant_id", on_delete: :nullify
  add_foreign_key "pods", "rounds"
  add_foreign_key "results", "event_participants"
  add_foreign_key "results", "results", column: "superseded_by_id", on_delete: :nullify, deferrable: :deferred
  add_foreign_key "results", "rounds"
  add_foreign_key "results", "users", column: "recorded_by_user_id", on_delete: :nullify
  add_foreign_key "rooms", "events"
  add_foreign_key "rounds", "events"
  add_foreign_key "seatings", "event_participants"
  add_foreign_key "seatings", "pods"
  add_foreign_key "sessions", "users"
end
