require "application_system_test_case"

class AskWithoutJavascriptTest < ApplicationSystemTestCase
  driven_by_desktop_without_javascript

  test "markers jump to their source cards without JavaScript" do
    ask "How much paid leave do I get?"
    assert_text "Reload this page to see the answer."
    answer_questions
    refresh

    click_on "Source 1"

    assert_selector "#source-1:target", text: "Employee Handbook"
  end
end
