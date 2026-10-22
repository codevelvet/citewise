# Retrieval searches exactly: an approximate HNSW scan can miss live rows while
# deleted embeddings are still in its graph, as after a re-ingest.
class RemoveHnswIndexFromChunkEmbeddings < ActiveRecord::Migration[8.1]
  def change
    remove_index :chunk_embeddings, "(embedding::vector(1024)) vector_cosine_ops",
      using: :hnsw,
      where: "model = 'voyage-4-lite' AND strategy = 'raw'",
      name: "index_chunk_embeddings_on_voyage_4_lite_raw_embedding"
  end
end
