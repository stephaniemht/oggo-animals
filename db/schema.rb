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

ActiveRecord::Schema[7.2].define(version: 2025_10_30_132548) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_trgm"
  enable_extension "plpgsql"

  create_table "carrier_professions", force: :cascade do |t|
    t.bigint "carrier_referential_id", null: false
    t.string "external_code"
    t.string "external_label"
    t.string "external_label_norm"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "species"
    t.index ["carrier_referential_id", "external_label_norm"], name: "idx_on_carrier_referential_id_external_label_norm_4917b5cfa4", unique: true
    t.index ["carrier_referential_id"], name: "index_carrier_professions_on_carrier_referential_id"
    t.index ["external_label_norm"], name: "index_carrier_professions_on_label_norm_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["species"], name: "index_carrier_professions_on_species"
  end

  create_table "carrier_referentials", force: :cascade do |t|
    t.bigint "carrier_id", null: false
    t.string "version_label"
    t.datetime "imported_at"
    t.string "source_filename"
    t.string "file_sha256"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["carrier_id", "source_filename", "file_sha256"], name: "index_carrier_refs_on_carrier_filename_sha", unique: true
    t.index ["carrier_id"], name: "index_carrier_referentials_on_carrier_id"
  end

  create_table "carriers", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "profession_mappings", force: :cascade do |t|
    t.bigint "profession_id"
    t.bigint "carrier_profession_id", null: false
    t.string "status"
    t.float "confidence"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["carrier_profession_id"], name: "index_profession_mappings_on_carrier_profession_id"
    t.index ["profession_id", "carrier_profession_id"], name: "idx_on_profession_id_carrier_profession_id_4b18c4b689", unique: true
    t.index ["profession_id"], name: "index_profession_mappings_on_profession_id"
  end

  create_table "profession_merge_logs", force: :cascade do |t|
    t.integer "source_id", null: false
    t.integer "target_id", null: false
    t.jsonb "source_attrs", default: {}, null: false
    t.integer "mapping_ids", default: [], array: true
    t.integer "synonym_ids", default: [], array: true
    t.integer "alias_created_id"
    t.datetime "performed_at", null: false
    t.datetime "undone_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["performed_at"], name: "index_profession_merge_logs_on_performed_at"
    t.index ["source_id"], name: "index_profession_merge_logs_on_source_id"
    t.index ["target_id"], name: "index_profession_merge_logs_on_target_id"
  end

  create_table "profession_synonyms", force: :cascade do |t|
    t.bigint "profession_id", null: false
    t.string "alias", null: false
    t.string "alias_norm", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alias_norm"], name: "index_profession_synonyms_on_alias_norm", unique: true
    t.index ["profession_id"], name: "index_profession_synonyms_on_profession_id"
  end

  create_table "professions", force: :cascade do |t|
    t.string "name"
    t.string "name_norm"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "animal_species"
    t.string "animal_kind"
    t.index ["animal_kind"], name: "index_professions_on_animal_kind"
    t.index ["animal_species"], name: "index_professions_on_animal_species"
    t.index ["name_norm"], name: "index_professions_on_name_norm", unique: true
    t.index ["name_norm"], name: "index_professions_on_name_norm_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  add_foreign_key "carrier_professions", "carrier_referentials"
  add_foreign_key "carrier_referentials", "carriers"
  add_foreign_key "profession_mappings", "carrier_professions"
  add_foreign_key "profession_mappings", "professions"
  add_foreign_key "profession_synonyms", "professions"
end
