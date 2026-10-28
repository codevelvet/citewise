require "application_system_test_case"

class SmallPhoneAskTest < ApplicationSystemTestCase
  driven_by_phone SMALL_PHONE

  test "the sheet takes at most half the screen, and the answer's last line can scroll above it" do
    ask_cited_question
    tap_on marker_after(PART_TIME)
    assert_selector "#source-sheet[open]"
    assert_padded_for_sheet

    sheet_height, viewport_height = evaluate_script("[ document.getElementById('source-sheet').offsetHeight, innerHeight ]")
    assert_operator sheet_height, :<=, viewport_height / 2.0

    # Scrolls the answer's last line to the top of the sheet, as far as the page allows.
    line_top, line_bottom, sheet_top = evaluate_script(<<~JS)
      (() => {
        const range = document.createRange()
        range.selectNodeContents(document.querySelector("a[data-citation-ids='3']").closest("p"))
        const line = () => [ ...range.getClientRects() ].at(-1)
        const sheet = document.getElementById("source-sheet")
        scrollBy({ top: line().bottom - sheet.getBoundingClientRect().top, behavior: "instant" })
        return [ line().top, line().bottom, sheet.getBoundingClientRect().top ]
      })()
    JS
    assert_operator line_top, :>=, 0
    assert_operator line_bottom, :<=, sheet_top + 0.5
  end
end
