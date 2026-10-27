require "test_helper"

class Question::PassageRendererTest < ActiveSupport::TestCase
  test "renders paragraphs, emphasis, code, lists, blockquotes, and headings" do
    html = render("## Carry-over\n\nUp to **5** days *carry* over, see `HR-12`.\n\n- one\n- two\n\n1. first\n\n> quoted\n\n```\ncode\n```")

    assert_equal "Carry-over", html.at_css("h2").text
    assert_equal "5", html.at_css("p strong").text
    assert_equal "carry", html.at_css("p em").text
    assert_equal "HR-12", html.at_css("p code").text
    assert_equal [ "one", "two" ], html.css("ul li").map(&:text)
    assert_equal "first", html.at_css("ol li").text
    assert_equal "quoted", html.at_css("blockquote p").text
    assert_equal "code\n", html.at_css("pre code").text
  end

  test "relative links become plain text" do
    html = render("See [the policy](/handbook/leave) and [notes](notes.md) and [top](#top).")

    assert_empty html.css("a")
    assert_equal "See the policy and notes and top.", html.text.strip
  end

  test "javascript and other non-http schemes become plain text" do
    html = render("[run](javascript:alert(1)) [mail](mailto:hr@example.com) [files](ftp://example.com/x) [data](data:text/html,hi)")

    assert_empty html.css("a")
    assert_equal "run mail files data", html.text.strip
  end

  test "http and https links without a host become plain text" do
    html = render("[one](https:foo) [two](http:/x)")

    assert_empty html.css("a")
    assert_equal "one two", html.text.strip
  end

  test "absolute links open in a new tab with noopener noreferrer" do
    html = render("Read [the article](https://example.com/plan) or <http://example.org>.")

    assert_equal [ [ "https://example.com/plan", "_blank", "noopener noreferrer", "the article" ],
                   [ "http://example.org", "_blank", "noopener noreferrer", "http://example.org" ] ],
                 html.css("a").map { [ it["href"], it["target"], it["rel"], it.text ] }
  end

  test "raw HTML is dropped, not escaped into view" do
    rendered = Question::PassageRenderer.render("Text <span onclick=\"x()\">inline</span> here.\n\n<div>block</div>\n\n<script>alert(1)</script>")

    assert_no_match(/<span|<div>|<script|onclick|&lt;|alert|raw HTML omitted/, rendered)
    assert_equal "Text inline here.", Nokogiri::HTML5.fragment(rendered).text.strip
  end

  test "images become their alt text" do
    html = render("Before ![The org chart](https://example.com/chart.png) after.")

    assert_empty html.css("img")
    assert_equal "Before The org chart after.", html.text.strip
  end

  test "tables sit in a focusable scrolling wrapper, without alignment attributes" do
    html = render("| Days | Notes |\n|:--|--:|\n| 5 | Carry over |")

    wrapper = html.at_css("div.passage-table")
    assert_equal [ "0", "region", "Table" ], [ wrapper["tabindex"], wrapper["role"], wrapper["aria-label"] ]
    assert_equal [ "Days", "Notes" ], wrapper.css("table thead th").map(&:text)
    assert_equal [ "5", "Carry over" ], wrapper.css("table tbody td").map(&:text)
    assert_nil html.at_css("[align], [style]")
  end

  test "is html safe" do
    assert_predicate Question::PassageRenderer.render("Plain."), :html_safe?
  end

  private
    def render(markdown)
      Nokogiri::HTML5.fragment(Question::PassageRenderer.render(markdown))
    end
end
