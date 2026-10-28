require "application_system_test_case"

class AskTest < ApplicationSystemTestCase
  test "asking shows the pending state, then the answer arrives by broadcast without a reload" do
    ask "How much paid leave do I get?"

    assert_selector "[data-question-status=pending]", text: "Finding the relevant passages"
    assert_subscribed_to_answer
    execute_script "window.notReloaded = true"

    answer_questions

    assert_selector "[data-question-status=answered] article", text: "Full-time employees accrue 20 days of paid leave per year."
    assert_selector "[role=status]", text: "The answer is ready.", visible: :all
    assert evaluate_script("window.notReloaded"), "the page reloaded"
  end

  test "the rail opens source 1, with nothing highlighted" do
    ask_cited_question

    assert_expanded true, false, false
    assert_highlighted
    assert_no_text "Cited here"
  end

  test "a marker opens its card in the rail and highlights its source's spans" do
    ask_cited_question

    assert_marker_selects_its_source_in_the_rail
  end

  test "a card header highlights its source's spans, without Cited here" do
    ask_cited_question

    card_button(2).click

    assert_selector "#source-2[data-selected]"
    assert_expanded false, true, false
    assert_highlighted CARRY_OVER, BOOKING
    assert_no_text "Cited here"
  end

  test "passages render links, images, raw HTML, and tables as specified" do
    ask_cited_question
    card_button(3).click

    within "#source-3" do
      link = find_link "the leave calculator", href: "https://example.com/leave-calculator"
      assert_equal [ "_blank", "noopener noreferrer" ], [ link[:target], link[:rel] ]
      assert_no_link "the handbook"
      assert_text "or read the handbook."
      assert_no_selector "img", visible: :all
      assert_text "Leave by hours chart"
      assert_no_text "Raw HTML block"
      assert_no_selector "[onclick], script", visible: :all

      table = find(".passage-table[role=region][aria-label=Table][tabindex='0']", text: "Hours per week")
      assert_matches_style table, "overflow-x" => "auto"
      table.execute_script "this.focus()"
      assert_selector ".passage-table:focus"
    end
  end

  test "widening past the breakpoint closes the sheet and resets the rail" do
    current_window.resize_to 800, 900
    ask_cited_question
    marker_after(CARRY_OVER).click
    assert_selector "#source-sheet[open]"

    current_window.resize_to 1100, 900

    assert_sheet_closed
    assert_expanded true, false, false
    assert_highlighted
    assert_no_selector "a[data-selected]"
  end
end
