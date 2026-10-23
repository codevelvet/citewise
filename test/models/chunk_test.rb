require "test_helper"

class ChunkTest < ActiveSupport::TestCase
  include TestData

  test "test data is valid" do
    assert chunks(:intro).valid?
    assert chunks(:leave).valid?
  end

  test "requires a document" do
    chunk = Chunk.new(position: 0, content: "Text", token_count: 1, content_hash: "abc")
    assert_not chunk.valid?
    assert_includes chunk.errors[:document], "must exist"
  end

  test "requires position, content, token_count, and content_hash" do
    chunk = documents(:pending_upload).chunks.new
    assert_not chunk.valid?
    assert_includes chunk.errors[:position], "is not a number"
    assert_includes chunk.errors[:content], "can't be blank"
    assert_includes chunk.errors[:token_count], "is not a number"
    assert_includes chunk.errors[:content_hash], "can't be blank"
  end

  test "rejects negative position and token_count" do
    chunk = documents(:pending_upload).chunks.new(position: -1, content: "Text", token_count: -1, content_hash: "abc")
    assert_not chunk.valid?
    assert_includes chunk.errors[:position], "must be greater than or equal to 0"
    assert_includes chunk.errors[:token_count], "must be greater than or equal to 0"
  end

  test "stores heading_path as an array and context as nullable" do
    chunk = chunks(:leave).reload
    assert_equal [ "Employee Handbook", "Benefits", "Paid leave" ], chunk.heading_path
    assert_nil chunk.context

    chunk.update!(context: "From the Benefits section of the Employee Handbook.")
    assert_equal "From the Benefits section of the Employee Handbook.", chunk.reload.context
  end

  test "defaults heading_path to an empty array" do
    chunk = documents(:pending_upload).chunks.create!(position: 0, content: "Text", token_count: 1, content_hash: "abc")
    assert_equal [], chunk.reload.heading_path
  end

  test "validates position uniqueness per document" do
    duplicate = documents(:handbook).chunks.new(position: 0, content: "Text", token_count: 1, content_hash: "abc")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:position], "has already been taken"
  end

  test "enforces position uniqueness per document in the database" do
    assert_raises ActiveRecord::RecordNotUnique do
      Chunk.insert_all!([ { document_id: documents(:handbook).id, position: 0, content: "Text", token_count: 1, content_hash: "abc" } ])
    end
  end

  test "source title is the heading path when it starts with the document title" do
    assert_equal "Employee Handbook > Benefits > Paid leave", chunks(:leave).source_title
  end

  test "source title adds the document title when the heading path doesn't start with it" do
    chunk = chunks(:leave)
    chunk.heading_path = [ "Benefits", "Paid leave" ]
    assert_equal "Employee Handbook > Benefits > Paid leave", chunk.source_title

    chunk.heading_path = []
    assert_equal "Employee Handbook", chunk.source_title
  end

  test "raw embedding input is the heading path joined with ' > ', a blank line, then the body" do
    expected = "Employee Handbook > Benefits > Paid leave\n\nFull-time employees accrue 20 days of paid leave per year."
    assert_equal expected, chunks(:leave).embedding_input(:raw)
    assert_equal expected, chunks(:leave).embedding_input("raw")
  end

  test "raw embedding input without a heading path is the body alone" do
    chunk = Chunk.new(content: "Body.", heading_path: [])
    assert_equal "Body.", chunk.embedding_input(:raw)
  end

  test "embedding input hash is the SHA-256 of the embedding input" do
    chunk = chunks(:leave)
    assert_equal Digest::SHA256.hexdigest(chunk.embedding_input(:raw)), chunk.embedding_input_hash(:raw)
  end

  test "contextual embedding input is not implemented yet" do
    assert_raises(NotImplementedError) { chunks(:leave).embedding_input(:contextual) }
  end

  test "rejects an unknown embedding strategy" do
    assert_raises(ArgumentError) { chunks(:leave).embedding_input(:hybrid) }
  end

  test "allows the same position in another document" do
    assert documents(:pending_upload).chunks.create(position: 0, content: "Text", token_count: 1, content_hash: "abc").persisted?
  end
end
