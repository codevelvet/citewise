require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  test "fixtures are valid" do
    assert documents(:handbook).valid?
    assert documents(:pending_upload).valid?
  end

  test "requires a title" do
    document = Document.new(source_type: :upload)
    assert_not document.valid?
    assert_includes document.errors[:title], "can't be blank"
  end

  test "rejects unknown source_type and ingestion_status" do
    document = Document.new(title: "Doc", source_type: "fax", ingestion_status: "lost")
    assert_not document.valid?
    assert_includes document.errors[:source_type], "is not included in the list"
    assert_includes document.errors[:ingestion_status], "is not included in the list"
  end

  test "defaults to pending with empty metadata" do
    document = Document.create!(title: "Doc", source_type: :upload)
    assert document.pending?
    assert_equal({}, document.reload.metadata)
  end

  test "attaches a file" do
    document = documents(:pending_upload)
    document.file.attach(io: StringIO.new("# Hello"), filename: "hello.md", content_type: "text/markdown")
    assert document.file.attached?
  end

  test "has many chunks and deletes them with the document" do
    document = documents(:handbook)
    assert_equal [ chunks(:intro), chunks(:leave) ], document.chunks.order(:position).to_a

    assert_difference -> { Chunk.count }, -2 do
      document.destroy
    end
  end

  test "validates source_uri uniqueness per source_type" do
    duplicate = Document.new(title: "Copy", source_type: :handbook, source_uri: "handbooks/employee.md")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_uri], "has already been taken"
  end

  test "enforces source_uri uniqueness per source_type in the database" do
    assert_raises ActiveRecord::RecordNotUnique do
      Document.insert_all!([ { title: "Copy", source_type: "handbook", source_uri: "handbooks/employee.md" } ])
    end
  end

  test "allows the same source_uri under another source_type" do
    assert Document.create(title: "Copy", source_type: :url, source_uri: "handbooks/employee.md").persisted?
  end

  test "allows many documents without a source_uri" do
    Document.insert_all!([
      { title: "One", source_type: "upload" },
      { title: "Two", source_type: "upload" }
    ])
    assert_equal 3, Document.where(source_type: :upload, source_uri: nil).count
  end
end
