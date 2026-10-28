require "application_system_test_case"

class AskWithoutJavascriptTest < ApplicationSystemTestCase
  driven_by_desktop_without_javascript

  test "without JavaScript, cards show every passage and markers jump to their source cards" do
    ask "How much paid leave do I get?"
    assert_text "Reload this page to see the answer."
    answer_cited_question
    refresh

    assert_no_selector "aside button", visible: :all
    assert_selector "aside blockquote", count: 4
    assert_selector "#source-2 blockquote", count: 2

    marker_after(BOOKING).click

    assert_selector "#source-2:target", text: "Leave Policy"
    outlines = %w[source-1 source-2].map { find("##{it}").style("border-color")["border-color"] }
    assert_not_equal(*outlines, "the targeted card has no outline")
    assert_sheet_closed
  end
end
