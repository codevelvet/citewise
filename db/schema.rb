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

ActiveRecord::Schema[8.1].define(version: 2026_10_21_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "chunk_embeddings", force: :cascade do |t|
    t.bigint "chunk_id", null: false
    t.string "model", null: false
    t.string "strategy", null: false
    t.integer "dimensions", null: false
    t.vector "embedding", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "input_hash", null: false
    t.index "((embedding)::vector(1024)) vector_cosine_ops", name: "index_chunk_embeddings_on_voyage_4_lite_raw_embedding", where: "(((model)::text = 'voyage-4-lite'::text) AND ((strategy)::text = 'raw'::text))", using: :hnsw
    t.index ["chunk_id", "model", "strategy"], name: "index_chunk_embeddings_on_chunk_id_and_model_and_strategy", unique: true
    t.check_constraint "vector_dims(embedding) = dimensions", name: "chunk_embeddings_embedding_matches_dimensions"
  end

  create_table "chunks", force: :cascade do |t|
    t.bigint "document_id", null: false
    t.integer "position", null: false
    t.text "content", null: false
    t.string "heading_path", default: [], null: false, array: true
    t.text "context"
    t.integer "token_count", null: false
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "position"], name: "index_chunks_on_document_id_and_position", unique: true
  end

  create_table "documents", force: :cascade do |t|
    t.string "title", null: false
    t.string "source_type", null: false
    t.string "source_uri"
    t.string "content_hash"
    t.string "ingestion_status", default: "pending", null: false
    t.datetime "ingested_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "chunker_fingerprint"
    t.text "ingestion_error"
    t.datetime "ingest_queued_at"
    t.datetime "embed_queued_at"
    t.index ["source_type", "source_uri"], name: "index_documents_on_source_type_and_source_uri", unique: true, where: "(source_uri IS NOT NULL)"
  end

  create_table "questions", force: :cascade do |t|
    t.text "text", null: false
    t.text "answer"
    t.string "status", default: "pending", null: false
    t.text "error"
    t.string "model"
    t.jsonb "retrieval", default: [], null: false
    t.jsonb "citations", default: [], null: false
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "cache_read_tokens"
    t.integer "cache_write_tokens"
    t.integer "retrieval_ms"
    t.integer "answer_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stop_reason"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chunk_embeddings", "chunks", on_delete: :cascade
  add_foreign_key "chunks", "documents", on_delete: :cascade
end
