# Creates the documents and chunks that model, job, and controller tests share,
# parents before children so each insert satisfies the foreign keys. Records keep
# the IDs their old YAML fixtures had: the anthropic_answerer cassette cites them.
module TestData
  extend ActiveSupport::Concern

  included do
    setup :create_test_data
  end

  def documents(*names)
    pick_test_records(@test_documents, names)
  end

  def chunks(*names)
    pick_test_records(@test_chunks, names)
  end

  private
    def create_test_data
      @test_documents = {}
      @test_chunks = {}

      create_test_document :handbook, title: "Employee Handbook", source_type: :filesystem, source_uri: "handbooks/employee.md",
        content_hash: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", ingestion_status: :ingested,
        ingested_at: 1.day.ago, metadata: { "collection" => "employee-handbook", "department" => "people" }
      create_test_document :pending_upload, title: "Pending Upload", source_type: :upload
      create_test_document :leave_policy, title: "Leave Policy", source_type: :filesystem, source_uri: "policies/leave.md",
        content_hash: "3e23e8160039594a33894f6564e1b1348bbd7a0088d42c4acb73eeaed59c009d", ingestion_status: :ingested,
        ingested_at: 1.day.ago

      create_test_chunk :intro, document: :handbook, position: 0,
        content: "Welcome to the company. This handbook explains how we work.",
        heading_path: [ "Employee Handbook", "Introduction" ], token_count: 12,
        content_hash: "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"
      create_test_chunk :leave, document: :handbook, position: 1,
        content: "Full-time employees accrue 20 days of paid leave per year.",
        heading_path: [ "Employee Handbook", "Benefits", "Paid leave" ], token_count: 13,
        content_hash: "fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9"
      # Several paragraphs, two of them merged-in subsections with inline headings.
      create_test_chunk :leave_details, document: :leave_policy, position: 0, content: <<~TEXT.chomp,
        Paid leave accrues monthly, at one twelfth of your yearly allowance.

        ### Carry-over

        Up to 5 unused days carry over into the next year. Days carried over must be used by March 31.

        ### Booking leave

        Book leave in the HR portal at least two weeks ahead. Your manager approves or declines within three working days.
      TEXT
        heading_path: [ "Leave Policy", "Benefits" ], token_count: 75,
        content_hash: "49f4f6f828ae0da93013891cabcda7d6dd24e8a50e0e4f7caa52ddf23281f37d"
    end

    def create_test_document(name, **attributes)
      @test_documents[name] = Document.create!(id: ActiveRecord::FixtureSet.identify(name), **attributes)
    end

    def create_test_chunk(name, document:, **attributes)
      @test_chunks[name] = Chunk.create!(id: ActiveRecord::FixtureSet.identify(name), document: @test_documents.fetch(document), **attributes)
    end

    def pick_test_records(records, names)
      found = names.map { records.fetch(it) }
      names.one? ? found.first : found
    end
end
