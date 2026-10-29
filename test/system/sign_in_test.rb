require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "a signed-out visitor signs in and lands on the page they asked for" do
    user = create_user

    visit new_question_path(text: "How much leave?")

    assert_selector "h1", text: "Sign in"
    assert_selector "input[type=email][autocomplete=username]"
    assert_selector "input[type=password][autocomplete=current-password]"
    fill_in "Email", with: user.email_address
    fill_in "Password", with: PASSWORD
    click_on "Sign in"

    assert_selector "h1", text: "Ask the handbook"
    assert_field "Your question", with: "How much leave?"
  end

  test "a wrong password keeps the visitor on the sign-in page with a message" do
    user = create_user

    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "not the password"
    click_on "Sign in"

    assert_selector "[role=alert]", text: "Try another email address or password."
    assert_no_button "Sign out"
  end

  test "signing out returns to the sign-in page, and the ask page needs signing in again" do
    sign_in

    click_on "Sign out"

    assert_selector "h1", text: "Sign in"
    visit root_path
    assert_selector "h1", text: "Sign in"
  end
end
