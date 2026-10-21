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

  test "folds a tiny tail of a split section back into the piece before it" do
    paragraphs = (1..4).map { |i| paragraph(i) }
    chunks = small_chunk("## Section\n\n#{paragraphs.join("\n\n")}\n\nTiny tail.\n", min_tokens: 10, target_tokens: 35)

    assert_equal [ paragraphs.first(2).join("\n\n"), "P2 s3 alpha beta gamma.\n\n#{paragraphs[2]}\n\n#{paragraphs[3]}\n\nTiny tail." ], chunks.map(&:content)
  end

  test "rejects an unknown merge policy" do
    assert_raises(ArgumentError) { Chunking::MarkdownChunker.new(merge_policy: :siblings) }
  end

  test "within_section: a tiny subsection merges into its larger parent, which keeps its path" do
    chunks = merge_chunk("## Parent\n\n#{paragraph(1)}\n\n### Child\n\nShort child.\n")

    assert_equal [ [ "Doc", "Parent" ] ], chunks.map(&:heading_path)
    assert_equal "#{paragraph(1)}\n\n### Child\n\nShort child.", chunks.first.content
  end

  test "within_section: a tiny parent intro does not take over its larger first subsection" do
    chunks = merge_chunk("## Parent\n\nIntro.\n\n### Child\n\n#{paragraph(1)}\n")

    assert_equal [ [ "Doc", "Parent" ], [ "Doc", "Parent", "Child" ] ], chunks.map(&:heading_path)
  end

  test "within_section: tiny siblings stay separate with their own paths" do
    chunks = merge_chunk("## Time off\n\n### One\n\nShort one.\n\n### Two\n\nShort two.\n")

    assert_equal [ [ "Doc", "Time off", "One" ], [ "Doc", "Time off", "Two" ] ], chunks.map(&:heading_path)
    assert_equal [ "Short one.", "Short two." ], chunks.map(&:content)
  end

  test "common_prefix: merges tiny sibling sections under their common heading" do
    chunks = merge_chunk("## Time off\n\n### One\n\nShort one.\n\n### Two\n\nShort two.\n", merge_policy: :common_prefix)

    assert_equal [ [ "Doc", "Time off" ] ], chunks.map(&:heading_path)
    assert_equal "### One\n\nShort one.\n\n### Two\n\nShort two.", chunks.first.content
  end

  test "common_prefix: a tiny parent intro merges forward into its first subsection" do
    chunks = merge_chunk("## Parent\n\nIntro.\n\n### Child\n\nChild body.\n", merge_policy: :common_prefix)

    assert_equal [ [ "Doc", "Parent" ] ], chunks.map(&:heading_path)
    assert_equal "Intro.\n\n### Child\n\nChild body.", chunks.first.content
  end

  test "common_prefix: keeps every heading below the common path when merging deeper sections" do
    chunks = merge_chunk("## A\n\n### B\n\n#### X\n\nX body.\n\n### C\n\nC body.\n", merge_policy: :common_prefix)

    assert_equal [ [ "Doc", "A" ] ], chunks.map(&:heading_path)
    assert_equal "### B\n\n#### X\n\nX body.\n\n### C\n\nC body.", chunks.first.content
  end

  test "none: never merges" do
    chunks = merge_chunk("## Parent\n\n#{paragraph(1)}\n\n### Child\n\nShort child.\n", merge_policy: :none)

    assert_equal [ [ "Doc", "Parent" ], [ "Doc", "Parent", "Child" ] ], chunks.map(&:heading_path)
  end

  test "no policy merges across top-level sections" do
    %i[within_section common_prefix].each do |policy|
      chunks = merge_chunk("## A\n\nShort a.\n\n## B\n\nShort b.\n", merge_policy: policy)

      assert_equal [ [ "Doc", "A" ], [ "Doc", "B" ] ], chunks.map(&:heading_path), policy
    end
  end

  test "no policy merges content that comes before the first heading" do
    %i[within_section common_prefix].each do |policy|
      chunks = merge_chunk("#{paragraph(1)}\n\n## A\n\nShort a.\n", merge_policy: policy)

      assert_equal [ [ "Doc" ], [ "Doc", "A" ] ], chunks.map(&:heading_path), policy
    end
  end

  test "a tiny section stays alone when merging would exceed max_tokens" do
    big = (1..3).map { |i| paragraph(i) }.join("\n\n")
    chunks = merge_chunk("## A\n\n#{big}\n\n### Tiny\n\nShort tiny body here.\n")

    assert_equal [ [ "Doc", "A" ], [ "Doc", "A", "Tiny" ] ], chunks.map(&:heading_path)
  end

  test "strips Hugo shortcode tags but keeps the text they wrap" do
    chunks = chunk(<<~MD)
      ## Section

      {{% note %}}
      Note text.
      {{% /note %}}

      After the note.

      {{% include "includes/take-gitlab-for-a-spin.md" %}}

      {{< figure src="diagram.png" >}}
    MD

    assert_equal "Note text.\n\nAfter the note.", chunks.first.content
  end

  test "a section of only shortcodes is skipped" do
    assert_empty chunk("## Section\n\n{{% include \"x.md\" %}}\n")
  end

  test "leaves shortcodes inside code blocks alone" do
    code = "```\n{{% note %}}\n```"

    assert_equal code, chunk("## Section\n\n#{code}\n").first.content
  end

  test "drops HTML blocks with no text and thematic breaks, keeps HTML with text" do
    chunks = chunk(<<~MD)
      ## Section

      <div style="overflow-x: auto">
      <div style="width: 1800px;">

      Body.

      </div>
      </div>

      ---

      <details><summary>More</summary>
    MD

    assert_equal "Body.\n\n<details><summary>More</summary>", chunks.first.content
  end

  test "drops HTML comments and empty tags even when a comment or attribute contains >" do
    chunks = chunk(<<~MD)
      Body.

      <!-- just a comment -->

      <!-- TODO: a -> b -->

      <div title="a > b"></div>
    MD

    assert_equal "Body.", chunks.first.content
  end

  test "keeps HTML blocks with text inside tags, including entities and script or style source" do
    blocks = [ "<div>\n<p>Real text</p>\n</div>", "<div>&nbsp;</div>", "<script>track()</script>", "<style>p { color: red }</style>" ]
    chunks = chunk("Body.\n\n#{blocks.join("\n\n")}\n")

    assert_equal [ "Body.", *blocks ].join("\n\n"), chunks.first.content
  end

  test "drops mermaid diagrams and logs how many were skipped" do
    log = StringIO.new
    chunks = chunk(<<~MD, logger: Logger.new(log))
      ## Roles

      Body.

      ```mermaid
      graph LR;
      ```

      ```ruby
      puts 1
      ```

      ``` mermaid
      graph TD;
      ```
    MD

    assert_equal "Body.\n\n```ruby\nputs 1\n```", chunks.first.content
    assert_includes log.string, "Skipped 2 mermaid code block(s)"
  end

  test "chunking the same file twice gives equal results" do
    markdown = file_fixture("handbook/gitlabengineering.md").read
    chunker = Chunking::MarkdownChunker.new

    assert_equal chunker.call(markdown, title: "Doc"), chunker.call(markdown, title: "Doc")
  end

  test "fingerprint combines the version with a short settings digest" do
    assert_match(/\A2:\h{12}\z/, Chunking::MarkdownChunker.new.fingerprint)
  end

  test "fingerprint is stable for the same settings" do
    settings = { target_tokens: 300, max_tokens: 400, min_tokens: 50, overlap_tokens: 20, merge_policy: :common_prefix }

    assert_equal Chunking::MarkdownChunker.new(**settings).fingerprint, Chunking::MarkdownChunker.new(**settings).fingerprint
    assert_equal Chunking::MarkdownChunker.new.fingerprint, Chunking::MarkdownChunker.new(logger: Logger.new(nil)).fingerprint
  end

  test "fingerprint changes when any setting changes" do
    default = Chunking::MarkdownChunker.new.fingerprint
    changes = [
      { target_tokens: 401 }, { max_tokens: 513 }, { min_tokens: 99 }, { overlap_tokens: 51 },
      { merge_policy: :none }, { token_counter: WordCounter.new }
    ]

    fingerprints = changes.map { |change| Chunking::MarkdownChunker.new(**change).fingerprint }
    assert_not_includes fingerprints, default
    assert_equal changes.size, fingerprints.uniq.size
  end

  test "fingerprint changes when the version changes" do
    bumped = Class.new(Chunking::MarkdownChunker) { const_set(:VERSION, Chunking::MarkdownChunker::VERSION + 1) }

    assert_not_equal Chunking::MarkdownChunker.new.fingerprint, bumped.new.fingerprint
    assert_equal Chunking::MarkdownChunker.new.fingerprint.split(":").last, bumped.new.fingerprint.split(":").last
  end

  private
    # Counts words, so sizes in these tests are easy to reason about.
    class WordCounter
      def count(text)
        text.split.size
      end
    end

    # Merging is off unless a test asks for it, so tiny inline sections stay separate.
    def chunk(markdown, title: "Doc", min_tokens: 0, **options)
      Chunking::MarkdownChunker.new(min_tokens: min_tokens, **options).call(markdown, title: title)
    end

    def small_chunk(markdown, target_tokens: 40, max_tokens: 50, overlap_tokens: 6, **options)
      chunk(markdown, target_tokens: target_tokens, max_tokens: max_tokens, overlap_tokens: overlap_tokens, token_counter: WordCounter.new, **options)
    end

    def merge_chunk(markdown, **options)
      small_chunk(markdown, min_tokens: 10, **options)
    end

    # Fifteen words in three sentences.
    def paragraph(number)
      (1..3).map { |sentence| "P#{number} s#{sentence} alpha beta gamma." }.join(" ")
    end
end
