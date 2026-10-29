require "application_system_test_case"

class PhoneAskTest < ApplicationSystemTestCase
  driven_by_phone
  setup { sign_in }

  test "asking on a phone shows the pending state, then the answer arrives by broadcast" do
    ask "How much paid leave do I get?"

    assert_selector "[data-question-status=pending]", text: "Finding the relevant passages"
    assert_subscribed_to_answer

    answer_questions

    assert_selector "[data-question-status=answered] article", text: "Full-time employees accrue 20 days of paid leave per year."
    assert_equal 393, evaluate_script("window.innerWidth")
  end

  test "tapping a marker opens the sheet on its source, highlighting only that sentence" do
    ask_cited_question

    tap_on marker_after(BOOKING)

    within "#source-sheet[open]" do
      assert_selector "#source-sheet-title:focus", text: "Leave Policy"
      assert_selector "[data-citations-target=sheetPath]", exact_text: "Leave Policy > Benefits"
      assert_text "Passage 2 of 2"
      assert_cited_here "Booking leave"
    end
    assert_highlighted BOOKING
    assert_matches_style find("#source-sheet"), "animation-name" => "sheet-up"
  end

  test "the pager steps through a source's passages" do
    ask_cited_question

    tap_on marker_after(CARRY_OVER)

    within "#source-sheet[open]" do
      assert_text "Passage 1 of 2"
      assert_text "Up to 5 unused days"
      assert_button "Previous passage", disabled: true

      click_on "Next passage"
      assert_text "Passage 2 of 2"
      assert_text "Book leave in the HR portal"
      assert_button "Next passage", disabled: true

      click_on "Previous passage"
      assert_text "Passage 1 of 2"
      assert_text "Up to 5 unused days"
    end
  end

  test "Escape and Close each close the sheet and return focus to the marker that opened it" do
    ask_cited_question

    assert_marker_opens_the_sheet_until_escape

    tap_on marker_after(PART_TIME)
    assert_selector "#source-sheet-title:focus", text: "Part-time Guide"
    click_on "Close source"

    assert_sheet_closed
    assert_selector "a[data-citation-ids='3']:focus"
    assert_highlighted
  end

  test "tapping another marker while the sheet is open swaps its content, and Escape returns to that marker" do
    ask_cited_question
    tap_on marker_after(PART_TIME)
    assert_selector "#source-sheet-title", text: "Part-time Guide"

    tap_on marker_after(LEAVE)

    within "#source-sheet[open]" do
      assert_selector "#source-sheet-title:focus", text: "Employee Handbook"
      assert_selector "[data-citations-target=sheetPath]", exact_text: "Employee Handbook > Benefits > Paid leave"
      assert_cited_here LEAVE
    end
    assert_highlighted LEAVE

    # The dialog alone would return focus to the first marker, which opened it.
    send_keys :escape

    assert_sheet_closed
    assert_selector "a[data-citation-ids='0']:focus"
  end

  test "the open sheet pads the page by its height" do
    ask_cited_question

    tap_on marker_after(PART_TIME)

    assert_selector "#source-sheet[open]"
    assert_padded_for_sheet
  end
end
