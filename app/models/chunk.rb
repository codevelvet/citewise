class Chunk < ApplicationRecord
  belongs_to :document
  has_many :embeddings, class_name: "ChunkEmbedding", dependent: :delete_all

  validates :content, :content_hash, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, uniqueness: { scope: :document_id }
  validates :token_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # The exact text indexed for this chunk under a ChunkEmbedding strategy. Every
  # embedding, and later the keyword-search index, must be built from this.
  def embedding_input(strategy)
    case strategy.to_s
    when "raw"
      # Heading path, blank line, body.
      [ heading_path.join(" > ").presence, content ].compact.join("\n\n")
    when "contextual"
      # Heading path, blank line, context, blank line, body. Lands with contextual retrieval.
      raise NotImplementedError, "the contextual strategy isn't implemented yet"
    else
      raise ArgumentError, "unknown strategy: #{strategy.inspect}"
    end
  end

  # Where the chunk sits, for showing alongside its text: "Employee Handbook > Benefits".
  # Heading paths usually start with the document's H1, which is its title,
  # so the title is added only when the path doesn't already start with it.
  def source_title
    path = heading_path.first == document.title ? heading_path : [ document.title, *heading_path ]
    path.join(" > ")
  end

  # Stored on ChunkEmbedding#input_hash; a mismatch means the embedding is stale.
  def embedding_input_hash(strategy)
    Digest::SHA256.hexdigest(embedding_input(strategy))
  end
end
