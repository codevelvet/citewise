require "test_helper"

# Chunks the real handbook pages with default settings and checks the invariants
# ingestion will rely on.
class Chunking::MarkdownChunkerHandbookTest < ActiveSupport::TestCase
  TITLES = {
    "gitlabegroupweekly.md" => "E-Group Weekly",
    "gitlabengineering.md" => "Engineering",
    "gitlabengineeringcareers.md" => "Engineering Career Development",
    "gitlabmission.md" => "GitLab Mission"
  }.freeze

  TITLES.each do |file, title|
    test "#{file}: chunks are numbered, titled, sized, and hashed" do
      chunks = chunk(file)

      assert_not_empty chunks
      assert_equal (0...chunks.size).to_a, chunks.map(&:position)
      chunks.each do |chunk|
        assert_equal title, chunk.heading_path.first, "heading_path #{chunk.heading_path} should start with the front matter title"
        assert_operator chunk.token_count, :<=, 512, "chunk #{chunk.position} is over max_tokens"
        assert_equal Chunking::TokenCounter::Approximate.new.count(chunk.content), chunk.token_count
        assert_equal Digest::SHA256.hexdigest(chunk.content), chunk.content_hash
      end
    end

    test "#{file}: merged chunks keep at least a top-level section in their path" do
      chunk(file).each do |chunk|
        merged = chunk.content.match?(/^#+ /)
        assert !merged || chunk.heading_path.size >= 2, "chunk #{chunk.position} merged up to the title"
      end
    end

    test "#{file}: code fences and tables are never split" do
      chunk(file).each do |chunk|
        assert_predicate chunk.content.scan(/^\s*```/).size, :even?, "chunk #{chunk.position} has an unclosed fence"
        if chunk.content.match?(/^\|/)
          assert_match(/^\|[-| :]+\|$/, chunk.content, "chunk #{chunk.position} has table rows without the table header")
        end
      end
    end

    test "#{file}: no shortcodes or mermaid diagrams in content" do
      chunk(file).each do |chunk|
        assert_no_match(/\{\{[<%]/, chunk.content)
        assert_no_match(/mermaid/, chunk.content)
      end
    end

    test "#{file}: every line of prose ends up in a chunk" do
      contents = chunk(file).map(&:content)
      body = read(file).split(/^---$/, 3).last.gsub(/^```mermaid$.*?^```$/m, "")

      body.lines.grep(/\A[[:alpha:]]/).map(&:strip).each do |line|
        assert contents.any? { |content| content.include?(line) }, "missing line: #{line}"
      end
    end
  end

  test "the interim roles table stays whole under its section" do
    table = read("gitlabengineeringcareers.md").lines.grep(/^\|/).first(10).join.rstrip
    chunk = chunk("gitlabengineeringcareers.md").find { |chunk| chunk.content.include?("| Current level") }

    assert_includes chunk.content, table
    assert_equal [ "Engineering Career Development", "Individual Contribution vs. Management", "Temporary Management Positions", "Types of Interim Roles", "Interim Manager" ], chunk.heading_path
  end

  test "a tiny sibling section stays standalone instead of blurring its neighbor's path" do
    paths = chunk("gitlabengineering.md").map(&:heading_path)

    assert_includes paths, [ "Engineering", "Engineering Culture", "Engineering Innovation" ]
    assert_includes paths, [ "Engineering", "Engineering Culture", "Technical Roadmaps" ]
  end

  test "the note shortcode around the time off process keeps its text" do
    chunk = chunk("gitlabengineering.md").find { |chunk| chunk.heading_path == [ "Engineering", "Engineering Culture", "Taking time off" ] }

    assert chunk.content.start_with?("This process is expected for PTO that is five consecutive days or more")
  end

  test "mermaid diagrams on the careers page are skipped and logged" do
    log = StringIO.new
    chunk("gitlabengineeringcareers.md", logger: Logger.new(log))

    assert_includes log.string, %(Skipped 4 mermaid code block(s) in "Engineering Career Development")
  end

  private
    def chunk(file, **options)
      Chunking::MarkdownChunker.new(**options).call(read(file), title: "Fallback title")
    end

    def read(file)
      file_fixture("handbook/#{file}").read
    end
end
