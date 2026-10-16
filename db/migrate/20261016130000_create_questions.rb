class CreateQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.text :text, null: false
      t.text :answer
      t.string :status, null: false, default: "pending"
      t.text :error
      t.string :model
      # Snapshots of the chunks as they were when answered; re-ingestion deletes chunks.
      t.jsonb :retrieval, null: false, default: []
      t.jsonb :citations, null: false, default: []
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.integer :cache_write_tokens
      t.integer :retrieval_ms
      t.integer :answer_ms

      t.timestamps
    end
  end
end
