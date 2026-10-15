class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.string :source_type, null: false
      t.string :source_uri
      t.string :content_hash
      t.string :ingestion_status, null: false, default: "pending"
      t.datetime :ingested_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :documents, [ :source_type, :source_uri ], unique: true, where: "source_uri IS NOT NULL"
  end
end
