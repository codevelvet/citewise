require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include StubHelper

  setup do
    Rails.configuration.x.ask_page[:rate_limit_store].clear
    @user = create_user
  end

  test "new shows the sign-in form" do
    get new_session_path

    assert_response :success
    assert_select "input[type=email][name=email_address][autocomplete=username]"
    assert_select "input[type=password][name=password][autocomplete=current-password]"
    assert_select "#ask-top", count: 0
    assert_select "button", text: "Sign out", count: 0
  end

  test "a signed-out visitor goes to sign-in, then back to the page they asked for" do
    get new_question_path(text: "How much leave?")
    assert_redirected_to new_session_path

    sign_in

    assert_redirected_to new_question_path(text: "How much leave?")
  end

  test "a signed-out request for an answer's stream doesn't become the page to return to" do
    question = Question.create!(text: "How much leave?")

    get answer_question_path(question, format: :turbo_stream)
    assert_redirected_to new_session_path

    sign_in

    assert_redirected_to root_url
  end

  test "a signed-out form submission doesn't become the page to return to" do
    post questions_path, params: { question: { text: "How much leave?" } }
    assert_redirected_to new_session_path

    sign_in

    assert_redirected_to root_url
  end

  test "signing in without a page to return to goes to the ask page" do
    sign_in

    assert_redirected_to root_url
  end

  test "the health check stays open" do
    get rails_health_check_path

    assert_response :success
  end

  test "signing in creates a session and sets its cookie" do
    assert_difference -> { @user.sessions.count }, 1 do
      sign_in
    end

    assert cookies[:session_id].present?
    follow_redirect!
    assert_response :success
    # A plain form, so it works without JavaScript.
    assert_select "header form[action=?][method=post]", session_path do
      assert_select "input[name=_method][value=delete]", visible: :all
      assert_select "button[type=submit]", "Sign out"
    end
  end

  test "a failed sign-in shows the same message whether or not the email exists" do
    messages = [ [ @user.email_address, "wrong password!" ], [ "nobody@example.com", PASSWORD ] ].map do |email_address, password|
      assert_no_difference -> { Session.count } do
        post session_path, params: { email_address: email_address, password: password }
      end
      assert_redirected_to new_session_path
      assert cookies[:session_id].blank?
      flash[:alert]
    end

    assert_equal [ "Try another email address or password." ] * 2, messages
  end

  test "sign-in allows 10 attempts in 3 minutes per IP" do
    # rate_limit took Rails.cache, a NullStore in tests, when the class loaded, and the
    # NullStore never counts. Forward its increments to a store that does. If Rails stops
    # counting this way, nothing counts and this test fails rather than passing falsely.
    counts = ActiveSupport::Cache::MemoryStore.new
    stub(Rails.cache, :increment, ->(*args, **options) { counts.increment(*args, **options) }) do
      10.times { post session_path, params: { email_address: @user.email_address, password: "wrong password!" } }
      assert_equal "Try another email address or password.", flash[:alert]

      assert_no_difference -> { Session.count } do
        sign_in
      end
      assert_redirected_to new_session_path
      assert_equal "Try again later.", flash[:alert]

      travel 3.minutes + 1.second do
        sign_in
        assert_redirected_to root_url
      end
    end
  end

  test "signing out destroys the session and its cookie" do
    sign_in
    session_record = @user.sessions.sole

    delete session_path

    assert_redirected_to new_session_path
    assert_not Session.exists?(session_record.id)
    assert cookies[:session_id].blank?
    get root_path
    assert_redirected_to new_session_path
  end

  test "a question asked before signing out isn't visible to the next user to sign in" do
    sign_in
    post questions_path, params: { question: { text: "How much leave?" } }
    question = Question.last
    get question_path(question)
    assert_response :success

    delete session_path
    sign_in create_user("other@example.com")
    get question_path(question)

    assert_response :not_found
  end

  test "with the ask page off, its routes 404 signed in or out" do
    Rails.configuration.x.ask_page[:enabled] = false

    [ root_path, new_question_path ].each do |path|
      get path
      assert_response :not_found
    end
    sign_in
    [ root_path, new_question_path ].each do |path|
      get path
      assert_response :not_found
    end
  ensure
    Rails.configuration.x.ask_page[:enabled] = true
  end

  private
    def sign_in(user = @user)
      post session_path, params: { email_address: user.email_address, password: PASSWORD }
    end
end
