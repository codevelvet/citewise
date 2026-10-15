class CreateChunkEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :chunk_embeddings do |t|
      t.references :chunk, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :model, null: false
      t.string :strategy, null: false
      t.integer :dimensions, null: false
      t.vector :embedding, null: false

      t.timestamps
    end

    add_index :chunk_embeddings, [ :chunk_id, :model, :strategy ], unique: true
    add_check_constraint :chunk_embeddings, "vector_dims(embedding) = dimensions", name: "chunk_embeddings_embedding_matches_dimensions"

    # The column has no fixed size, so the index casts to the one configuration it serves.
    # Queries must use the same cast and predicate to hit it.
    add_index :chunk_embeddings, "(embedding::vector(1024)) vector_cosine_ops",
      using: :hnsw,
      where: "model = 'voyage-4-lite' AND strategy = 'raw'",
      name: "index_chunk_embeddings_on_voyage_4_lite_raw_embedding"
  end
end
