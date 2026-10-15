class ChunkEmbedding < ApplicationRecord
  belongs_to :chunk

  has_neighbors :embedding

  enum :strategy, { raw: "raw", contextual: "contextual" }, validate: true

  validates :model, :embedding, presence: true
  validates :model, uniqueness: { scope: [ :chunk_id, :strategy ] }
  validates :dimensions, numericality: { only_integer: true, greater_than: 0 }
  validate :embedding_matches_dimensions

  private
    def embedding_matches_dimensions
      if embedding.present? && dimensions.present? && embedding.size != dimensions
        errors.add(:embedding, "must have #{dimensions} dimensions (has #{embedding.size})")
      end
    end
end
