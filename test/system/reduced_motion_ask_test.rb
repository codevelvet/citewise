require "application_system_test_case"

class ReducedMotionAskTest < ApplicationSystemTestCase
  driven_by_phone reduced_motion: true
  setup { sign_in }

  test "the sheet opens without animation" do
    ask_cited_question

    tap_on marker_after(CARRY_OVER)

    assert_selector "#source-sheet[open]"
    assert_matches_style find("#source-sheet"), "animation-name" => "none"
  end
end
