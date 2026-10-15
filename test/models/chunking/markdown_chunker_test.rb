require "test_helper"

class Chunking::MarkdownChunkerTest < ActiveSupport::TestCase
  test "empty input yields no chunks" do
    assert_empty chunk("")
    assert_empty chunk("  \n\n ")
  end

  test "a document without headings is one chunk under the title" do
    chunks = chunk("First paragraph.\n\nSecond paragraph.\n")

    assert_equal 1, chunks.size
    assert_equal [ "Doc" ], chunks.first.heading_path
    assert_equal "First paragraph.\n\nSecond paragraph.", chunks.first.content
  end

  test "a document with only headings yields no chunks" do
    assert_empty chunk("# One\n\n## Two\n\n### Three\n")
  end

  test "splits on headings and tracks the heading path" do
    chunks = chunk(<<~MD)
      Intro.

      ## Alpha

      Alpha body.

      ### Alpha one

      Alpha one body.

      ## Beta

      Beta body.
    MD

    assert_equal [ [ "Doc" ], [ "Doc", "Alpha" ], [ "Doc", "Alpha", "Alpha one" ], [ "Doc", "Beta" ] ], chunks.map(&:heading_path)
    assert_equal [ "Intro.", "Alpha body.", "Alpha one body.", "Beta body." ], chunks.map(&:content)
    assert_equal [ 0, 1, 2, 3 ], chunks.map(&:position)
  end

  test "deep nesting and skipped levels leave no gaps in the path" do
    chunks = chunk(<<~MD)
      ## Two

      #### Four

      ###### Six

      Deep body.

      ### Three

      Shallower body.
    MD

    assert_equal [ [ "Doc", "Two", "Four", "Six" ], [ "Doc", "Two", "Three" ] ], chunks.map(&:heading_path)
  end

  test "heading text is plain text without Markdown markup" do
    chunks = chunk("## Use `bin/ci` and *read* [the docs](/docs)\n\nBody.\n")

    assert_equal [ "Doc", "Use bin/ci and read the docs" ], chunks.first.heading_path
  end

  test "strips front matter and uses its title" do
    chunks = chunk(<<~MD)
      ---
      title: "From Front Matter"
      date: 2024-01-02
      ---

      Body.
    MD

    assert_equal [ [ "From Front Matter" ] ], chunks.map(&:heading_path)
    assert_equal "Body.", chunks.first.content
  end

  test "falls back to the given title when front matter has none or is malformed" do
    assert_equal [ "Doc" ], chunk("---\ndescription: x\n---\nBody.\n").first.heading_path
    assert_equal [ "Doc" ], chunk("---\ntitle: [unclosed\n---\nBody.\n").first.heading_path
  end

  test "keeps the original Markdown of each block" do
    markdown = <<~MD
      ## Section

      - one
      - **two**

      > quoted
    MD

    assert_equal "- one\n- **two**\n\n> quoted", chunk(markdown).first.content
  end

  test "fills token_count and content_hash from the content" do
    chunk = chunk("## Section\n\nSome body text.\n").first

    assert_equal 4, chunk.token_count
    assert_equal Digest::SHA256.hexdigest("Some body text."), chunk.content_hash
  end

  test "rejects inconsistent size settings" do
    assert_raises(ArgumentError) { Chunking::MarkdownChunker.new(target_tokens: 600, max_tokens: 512) }
    assert_raises(ArgumentError) { Chunking::MarkdownChunker.new(target_tokens: 100, overlap_tokens: 100) }
  end

  test "a section under max_tokens stays whole" do
    chunks = small_chunk("## Section\n\n#{paragraph(1)}\n\n#{paragraph(2)}\n\n#{paragraph(3)}\n", max_tokens: 50)

    assert_equal 1, chunks.size
  end

  test "splits an oversized section on paragraph boundaries, repeating the last sentence as overlap" do
    paragraphs = (1..6).map { |i| paragraph(i) }
    chunks = small_chunk("## Section\n\n#{paragraphs.join("\n\n")}\n")

    assert_equal [ [ "Doc", "Section" ] ] * 3, chunks.map(&:heading_path)
    assert_equal "#{paragraphs[0]}\n\n#{paragraphs[1]}", chunks[0].content
    assert_equal "P2 s3 alpha beta gamma.\n\n#{paragraphs[2]}\n\n#{paragraphs[3]}", chunks[1].content
    assert_equal "P4 s3 alpha beta gamma.\n\n#{paragraphs[4]}\n\n#{paragraphs[5]}", chunks[2].content
    chunks.each { |chunk| assert_operator chunk.token_count, :<=, 40 }
  end

  test "overlap can be turned off" do
    paragraphs = (1..6).map { |i| paragraph(i) }
    chunks = small_chunk("## Section\n\n#{paragraphs.join("\n\n")}\n", overlap_tokens: 0)

    assert_equal paragraphs.join("\n\n"), chunks.map(&:content).join("\n\n")
  end

  test "never splits a code block, even one larger than max_tokens, and never overlaps from it" do
    code = "```ruby\n#{Array.new(100) { |i| "puts #{i}. # line" }.join("\n")}\n```"
    chunks = small_chunk("## Section\n\n#{paragraph(1)}\n\n#{code}\n\n#{paragraph(2)}\n")

    assert_equal [ paragraph(1), code, paragraph(2) ], chunks.map(&:content)
    assert_operator chunks[1].token_count, :>, 50
  end

  test "never splits a table" do
    table = "| a | b |\n|---|---|\n#{Array.new(40) { |i| "| row #{i}. | value |" }.join("\n")}"
    chunks = small_chunk("## Section\n\n#{paragraph(1)}\n\n#{table}\n\n#{paragraph(2)}\n")

    assert_equal [ paragraph(1), table, paragraph(2) ], chunks.map(&:content)
  end

  test "splits a long list between its items" do
    items = (1..10).map { |i| "- Item #{i} alpha beta gamma delta epsilon." }
    chunks = small_chunk("## Section\n\n#{items.join("\n")}\n", overlap_tokens: 0)

    assert_operator chunks.size, :>, 1
    assert_equal items, chunks.flat_map { |chunk| chunk.content.split("\n\n") }
  end

  test "leaves a single paragraph larger than max_tokens whole" do
    long = Array.new(80) { |i| "Sentence #{i} here." }.join(" ")
    chunks = small_chunk("## Section\n\n#{paragraph(1)}\n\n#{long}\n")

    assert_equal [ paragraph(1), long ], chunks.map(&:content)
    assert_operator chunks.last.token_count, :>, 50
  end

  private
    # Counts words, so sizes in these tests are easy to reason about.
    class WordCounter
      def count(text)
        text.split.size
      end
    end

    def chunk(markdown, title: "Doc", **options)
      Chunking::MarkdownChunker.new(**options).call(markdown, title: title)
    end

    def small_chunk(markdown, target_tokens: 40, max_tokens: 50, overlap_tokens: 6, **options)
      chunk(markdown, target_tokens: target_tokens, max_tokens: max_tokens, overlap_tokens: overlap_tokens, token_counter: WordCounter.new, **options)
    end

    # Fifteen words in three sentences.
    def paragraph(number)
      (1..3).map { |sentence| "P#{number} s#{sentence} alpha beta gamma." }.join(" ")
    end
end
