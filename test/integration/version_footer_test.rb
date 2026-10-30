require "test_helper"

class VersionFooterTest < ActionDispatch::IntegrationTest
  setup do
    @original = Rails.configuration.x.revision
    Rails.configuration.x.revision = "0123abc"
  end

  teardown do
    Rails.configuration.x.revision = @original
  end

  test "a signed-in user sees the deployed version in the footer" do
    sign_in_as create_user
    get new_question_path

    assert_select "footer", text: "Version 0123abc"
  end

  test "a signed-out visitor sees no version" do
    get new_session_path

    assert_response :success
    assert_select "footer", count: 0
    assert_no_match "0123abc", response.body
  end

  test "no footer when the version is unknown" do
    Rails.configuration.x.revision = nil
    sign_in_as create_user
    get new_question_path

    assert_response :success
    assert_select "footer", count: 0
  end

  # Outside production, config.x.revision is never set and reads back as empty options.
  test "no footer when the revision was never set" do
    Rails.configuration.x.revision = ActiveSupport::OrderedOptions.new
    sign_in_as create_user
    get new_question_path

    assert_response :success
    assert_select "footer", count: 0
  end
end
