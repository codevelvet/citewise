module Chunking
  # One chunk of a document, shaped like a row of the chunks table.
  Chunk = Data.define(:content, :heading_path, :position, :token_count, :content_hash)
end
