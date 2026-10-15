class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :chunks do |t|
      t.references :document, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :content, null: false
      t.string :heading_path, array: true, null: false, default: []
      t.text :context
      t.integer :token_count, null: false
      t.string :content_hash, null: false

      t.timestamps
    end

    add_index :chunks, [ :document_id, :position ], unique: true
  end
end
