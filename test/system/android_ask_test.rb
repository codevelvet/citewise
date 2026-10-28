require "application_system_test_case"

# The phone flow once more in Chromium, for Android.
class AndroidAskTest < ApplicationSystemTestCase
  driven_by_phone ANDROID_PHONE, browser: :chromium

  test "tapping a marker opens the sheet, and Escape closes it" do
    ask_cited_question

    assert_marker_opens_the_sheet_until_escape
  end
end
