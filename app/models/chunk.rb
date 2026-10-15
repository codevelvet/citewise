class Chunk < ApplicationRecord
  belongs_to :document

  validates :content, :content_hash, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, uniqueness: { scope: :document_id }
  validates :token_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
