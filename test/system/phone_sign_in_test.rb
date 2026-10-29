require "application_system_test_case"

# Signing in on an iPhone, in WebKit.
class PhoneSignInTest < ApplicationSystemTestCase
  driven_by_phone

  test "signing in on a phone fits the screen and lands on the page asked for" do
    user = create_user

    visit new_question_path(text: "How much leave?")

    assert_selector "h1", text: "Sign in"
    assert_selector "input[type=email][autocomplete=username]"
    assert_selector "input[type=password][autocomplete=current-password]"
    assert evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "the sign-in page scrolls sideways"

    fill_in "Email", with: user.email_address
    fill_in "Password", with: PASSWORD
    click_on "Sign in"

    assert_field "Your question", with: "How much leave?"
    assert_button "Sign out"
    assert evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "the ask page scrolls sideways"
  end
end
