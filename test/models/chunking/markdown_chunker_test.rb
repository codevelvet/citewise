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

  private
    def chunk(markdown, title: "Doc", **options)
      Chunking::MarkdownChunker.new(**options).call(markdown, title: title)
    end
end
