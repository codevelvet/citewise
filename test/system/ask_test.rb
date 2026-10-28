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

  test "a marker jumps to its source card" do
    ask "How much paid leave do I get?"
    assert_subscribed_to_answer
    answer_questions

    click_on "Source 1"

    # Turbo moves to the anchor with pushState, which doesn't set :target, so check the URL.
    assert_current_path(/#source-1\z/, url: true)
    assert_selector "#source-1", text: "Employee Handbook"
  end
end
