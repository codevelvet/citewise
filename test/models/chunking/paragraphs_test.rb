require "test_helper"

class Chunking::ParagraphsTest < ActiveSupport::TestCase
  test "splits on blank lines" do
    assert_equal [ "First paragraph,\nwrapped.", "Second paragraph.", "- a list\n- of items" ],
                 split("First paragraph,\nwrapped.\n\nSecond paragraph.\n\n\n- a list\n- of items\n")
  end

  test "keeps a code fence whole when it contains blank lines" do
    fence = "```ruby\ndef leave\n\n  20\n\n# not a heading\nend\n```"
    tildes = "~~~~\none\n\n~~~\ntwo\n~~~~"

    assert_equal [ "Before:", fence, "Between.", tildes, "After." ], split("Before:\n\n#{fence}\n\nBetween.\n\n#{tildes}\n\nAfter.")
  end

  test "an unclosed code fence runs to the end" do
    assert_equal [ "Intro.", "```\ncode\n\nmore code" ], split("Intro.\n\n```\ncode\n\nmore code")
  end

  test "keeps a table whole" do
    table = "| Type | Days |\n| --- | --- |\n| Annual | 20 |\n| Sick | 10 |"

    assert_equal [ "Leave by type:", table, "Ask HR for others." ], split("Leave by type:\n\n#{table}\n\nAsk HR for others.")
  end

  test "attaches an inline heading to the paragraph after it" do
    content = "We ship weekly.\n\n### Engineering Excellence\n\nWe review every change.\n\nTests are required."

    assert_equal [ "We ship weekly.", "### Engineering Excellence\n\nWe review every change.", "Tests are required." ], split(content)
  end

  test "attaches consecutive headings to the next paragraph" do
    assert_equal [ "## Benefits\n\n### Paid leave\n\n20 days." ], split("## Benefits\n\n### Paid leave\n\n20 days.")
  end

  test "a single paragraph is one block" do
    assert_equal [ "Full-time employees accrue 20 days of paid leave per year." ],
                 split("Full-time employees accrue 20 days of paid leave per year.")
  end

  test "empty input has no blocks" do
    assert_equal [], split("")
    assert_equal [], split(" \n\n  \n")
    assert_equal [], split(nil)
  end

  private
    def split(content)
      Chunking::Paragraphs.split(content)
    end
end
