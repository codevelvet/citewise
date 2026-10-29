require "application_system_test_case"

class SmallPhoneAskTest < ApplicationSystemTestCase
  driven_by_phone SMALL_PHONE
  setup { sign_in }

  test "the sheet takes at most half the screen, and the end of the page can scroll above it" do
    ask_cited_question
    tap_on marker_after(PART_TIME)
    assert_selector "#source-sheet[open]"
    assert_padded_for_sheet

    sheet_height, viewport_height = evaluate_script("[ document.getElementById('source-sheet').offsetHeight, innerHeight ]")
    assert_operator sheet_height, :<=, viewport_height / 2.0

    # Sources stack below the answer, so the last card ends the page. Without the padding it
    # would stay under the sheet. The sheet's top comes from layout, not its bounding box,
    # which its slide-up animation moves.
    card_bottom, sheet_top = evaluate_script(<<~JS)
      (() => {
        scrollTo({ top: document.scrollingElement.scrollHeight, behavior: "instant" })
        return [ document.getElementById("source-3").getBoundingClientRect().bottom,
                 innerHeight - document.getElementById("source-sheet").offsetHeight ]
      })()
    JS
    assert_operator card_bottom, :<=, sheet_top + 0.5
  end
end
