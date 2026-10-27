require "application_system_test_case"

class PhoneAskTest < ApplicationSystemTestCase
  driven_by_phone

  test "asking on a phone shows the pending state, then the answer arrives by broadcast" do
    ask "How much paid leave do I get?"

    assert_selector "[data-question-status=pending]", text: "Finding the relevant passages"
    assert_subscribed_to_answer

    answer_questions

    assert_selector "[data-question-status=answered] article", text: "Full-time employees accrue 20 days of paid leave per year."
    assert_equal 393, evaluate_script("window.innerWidth")
  end
end
