require "test_helper"

class ChunkTest < ActiveSupport::TestCase
  test "fixtures are valid" do
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

  test "allows the same position in another document" do
    assert documents(:pending_upload).chunks.create(position: 0, content: "Text", token_count: 1, content_hash: "abc").persisted?
  end
end
