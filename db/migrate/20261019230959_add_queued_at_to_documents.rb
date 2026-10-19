class AddQueuedAtToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :ingest_queued_at, :datetime
    add_column :documents, :embed_queued_at, :datetime
  end
end
