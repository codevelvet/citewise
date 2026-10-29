require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "a password needs at least 12 characters" do
    user = User.new(email_address: "owner@example.com", password: "a" * 11)
    assert_not user.valid?
    assert_includes user.errors.full_messages, "Password is too short (minimum is 12 characters)"

    user.password = "a" * 12
    assert user.valid?
  end

  test "saving without changing the password skips the length check" do
    user = create_user
    assert User.find(user.id).update(email_address: "new@example.com")
  end
end
