class AddIngestionFieldsToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :chunker_fingerprint, :string
    add_column :documents, :ingestion_error, :text
  end
end
