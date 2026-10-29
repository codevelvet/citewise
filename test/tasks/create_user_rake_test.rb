require "test_helper"
require "rake"

class CreateUserRakeTest < ActiveSupport::TestCase
  NEW_PASSWORD = "a brand new passphrase"

  # Stands in for a terminal on $stdin. getpass mirrors IO#getpass: it prompts on stderr
  # and returns the line without its newline, or nil at end of input.
  class FakeTerminal
    def initialize(input, tty:)
      @input = StringIO.new(input)
      @tty = tty
    end

    def tty? = @tty
    def gets = @input.gets

    def getpass(prompt)
      $stderr.print prompt
      @input.gets&.chomp
    end
  end

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "citewise:create_user" }
  end

  test "creates a user whose password is the typed line without its newline" do
    output, error = create_user_task("owner@example.com\n#{NEW_PASSWORD}\n#{NEW_PASSWORD}\n")

    assert_nil error
    assert_includes output, "Created user owner@example.com"
    assert_equal User.find_by!(email_address: "owner@example.com"), User.authenticate_by(email_address: "owner@example.com", password: NEW_PASSWORD)
    assert_nil User.authenticate_by(email_address: "owner@example.com", password: "#{NEW_PASSWORD}\n")
    assert_not_includes output, NEW_PASSWORD
  end

  test "an existing email gets the new password, and its sessions are signed out" do
    user = create_user
    other = create_user("other@example.com")
    2.times { user.sessions.create! }
    other.sessions.create!

    output, error = assert_no_difference(-> { User.count }) do
      create_user_task(" OWNER@example.com \n#{NEW_PASSWORD}\n#{NEW_PASSWORD}\n")
    end

    assert_nil error
    assert_includes output, "Set a new password for owner@example.com and signed out 2 sessions"
    assert_nil User.authenticate_by(email_address: user.email_address, password: PASSWORD)
    assert_equal user, User.authenticate_by(email_address: user.email_address, password: NEW_PASSWORD)
    assert_empty user.sessions.reload
    assert_equal 1, other.sessions.count
    assert_not_includes output, NEW_PASSWORD
  end

  test "mismatched passwords change nothing" do
    user = create_user
    user.sessions.create!

    output, error = create_user_task("owner@example.com\n#{NEW_PASSWORD}\nsomething else entirely\n")

    assert_equal "The passwords don't match", error.message
    assert_equal user, User.authenticate_by(email_address: user.email_address, password: PASSWORD)
    assert_equal 1, user.sessions.count
    assert_not_includes output, NEW_PASSWORD
  end

  test "a password under 12 characters is refused with the validation message" do
    output, error = assert_no_difference(-> { User.count }) do
      create_user_task("owner@example.com\nshort pass\nshort pass\n")
    end

    assert_equal "Password is too short (minimum is 12 characters)", error.message
    assert_not_includes output, "short pass"
  end

  test "end of input aborts before anything is saved" do
    [ "", "owner@example.com\n", "owner@example.com\n#{NEW_PASSWORD}\n" ].each do |input|
      _output, error = assert_no_difference(-> { User.count }) { create_user_task(input) }

      assert_kind_of SystemExit, error
    end
  end

  test "without a terminal it aborts before reading anything" do
    output, error = create_user_task("owner@example.com\n#{NEW_PASSWORD}\n#{NEW_PASSWORD}\n", tty: false)

    assert_match(/needs an interactive terminal/, error.message)
    assert_not_includes output, "Email:"
    assert_equal 0, User.count
  end

  private
    # Returns stdout and stderr together, and the SystemExit if the task aborted.
    def create_user_task(input, tty: true)
      stdin, $stdin = $stdin, FakeTerminal.new(input, tty: tty)
      task = Rake::Task["citewise:create_user"]
      task.reenable
      error = nil
      output = capture_io do
        task.invoke
      rescue SystemExit => exit
        error = exit
      end
      [ output.join, error ]
    ensure
      $stdin = stdin
    end
end
