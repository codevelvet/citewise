require "application_system_test_case"

# The rail flow once more in WebKit, for Safari on Macs.
class WebkitDesktopAskTest < ApplicationSystemTestCase
  driven_by_desktop browser: :webkit

  test "a marker opens its card in the rail and highlights its source's spans" do
    ask_cited_question

    assert_marker_selects_its_source_in_the_rail
  end
end
