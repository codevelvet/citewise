class AddInputHashToChunkEmbeddings < ActiveRecord::Migration[8.1]
  def change
    # SHA-256 of the exact text that was embedded; a mismatch means the embedding is stale.
    add_column :chunk_embeddings, :input_hash, :string, null: false
  end
end
