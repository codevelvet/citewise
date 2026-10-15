require "test_helper"
require "rake"

class CitewiseRakeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "citewise:reingest" }
    @dir = Pathname(Dir.mktmpdir)
    @dir.join("guides").mkpath
    @dir.join("intro.md").write("# Intro\n\nWelcome.\n")
    @dir.join("guides/setup.md").write("# Setup\n\nInstall it.\n")
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  test "import creates a filesystem document per Markdown file and enqueues ingestion" do
    output = nil
    assert_enqueued_jobs(2, only: IngestDocumentJob) { output = import }

    assert_includes output, "Created 2, updated 0, unchanged 0"
    documents = Document.filesystem.where(source_uri: [ "intro.md", "guides/setup.md" ]).order(:source_uri)
    assert_equal [ "guides/setup.md", "intro.md" ], documents.map(&:source_uri)
    documents.each do |document|
      assert_equal "test-collection", document.metadata["collection"]
      assert document.file.attached?
      assert_enqueued_with(job: IngestDocumentJob, args: [ document ])
    end
  end

  test "re-importing the same directory updates rather than duplicates" do
    import
    clear_enqueued_jobs

    output = nil
    assert_no_difference(-> { Document.count }) { assert_no_enqueued_jobs(only: IngestDocumentJob) { output = import } }
    assert_includes output, "Created 0, updated 0, unchanged 2"

    @dir.join("intro.md").write("# Intro\n\nWelcome back.\n")
    assert_no_difference(-> { Document.count }) { assert_enqueued_jobs(1, only: IngestDocumentJob) { output = import } }
    assert_includes output, "Created 0, updated 1, unchanged 1"
    assert_equal "# Intro\n\nWelcome back.\n", Document.find_by!(source_uri: "intro.md").file.download
  end

  test "reingest enqueues outdated and failed documents that have a file" do
    current = Ingestion::DocumentIngester.new.fingerprint
    outdated = create_document("outdated", chunker_fingerprint: "0:000000000000", ingestion_status: :ingested)
    failed = create_document("failed", chunker_fingerprint: current, ingestion_status: :failed)
    create_document("current", chunker_fingerprint: current, ingestion_status: :ingested)
    # documents(:pending_upload) has no file: it is outdated, but an upload in progress.

    output = nil
    assert_enqueued_jobs(2, only: IngestDocumentJob) { output = reingest }

    assert_includes output, "Enqueued 2"
    assert_enqueued_with(job: IngestDocumentJob, args: [ outdated, { force: true } ])
    assert_enqueued_with(job: IngestDocumentJob, args: [ failed, { force: true } ])
  end

  test "reingest all enqueues every document that has a file" do
    current = Ingestion::DocumentIngester.new.fingerprint
    documents = [ create_document("one", chunker_fingerprint: current, ingestion_status: :ingested), create_document("two") ]

    output = nil
    assert_enqueued_jobs(2, only: IngestDocumentJob) { output = reingest("all") }

    assert_includes output, "Enqueued 2"
    documents.each { |document| assert_enqueued_with(job: IngestDocumentJob, args: [ document, { force: true } ]) }
  end

  private
    def import
      run_task("citewise:import:directory", @dir.to_s, "test-collection")
    end

    def reingest(*args)
      run_task("citewise:reingest", *args)
    end

    def run_task(name, *args)
      task = Rake::Task[name]
      task.reenable
      capture_io { task.invoke(*args) }.first
    end

    def create_document(title, **attributes)
      Document.create!(title: title, source_type: :upload, **attributes).tap do |document|
        document.file.attach(io: StringIO.new("# #{title}\n"), filename: "#{title}.md", content_type: "text/markdown")
      end
    end
end
