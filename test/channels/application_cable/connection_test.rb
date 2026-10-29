require "test_helper"

# Answers arrive by broadcast, so the cable needs the same sign-in as the pages.
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with a signed-in session's cookie, identified by its user" do
    user = create_user
    cookies.signed[:session_id] = user.sessions.create!.id

    connect

    assert_equal user, connection.current_user
  end

  test "rejects a connection without a session cookie" do
    assert_reject_connection { connect }
  end

  test "rejects a connection whose session was signed out" do
    session = create_user.sessions.create!
    cookies.signed[:session_id] = session.id
    session.destroy!

    assert_reject_connection { connect }
  end

  test "rejects an unsigned session cookie" do
    cookies[:session_id] = create_user.sessions.create!.id

    assert_reject_connection { connect }
  end
end
