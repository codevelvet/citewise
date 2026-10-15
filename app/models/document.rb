class Document < ApplicationRecord
  has_one_attached :file

  enum :source_type, { upload: "upload", handbook: "handbook", url: "url" }, validate: true
  enum :ingestion_status, { pending: "pending", processing: "processing", ingested: "ingested", failed: "failed" }, validate: true

  validates :title, presence: true
  validates :source_uri, uniqueness: { scope: :source_type }, allow_nil: true
end
