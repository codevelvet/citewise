require "test_helper"

class RevisionConfigTest < ActiveSupport::TestCase
  test "production's revision is RENDER_GIT_COMMIT, shortened to seven characters" do
    assert_equal "0123abc", production_revision("0123abcdef456789")
  end

  test "production's revision is nil when RENDER_GIT_COMMIT is unset or empty" do
    assert_nil production_revision(nil)
    assert_nil production_revision("")
  end

  test "development and test set no revision" do
    assert_instance_of EnvironmentConfig::Recorder, EnvironmentConfig.load("development").x.revision
    assert_instance_of EnvironmentConfig::Recorder, EnvironmentConfig.load("test").x.revision
  end

  private
    # production.rb reads RENDER_GIT_COMMIT when it's evaluated.
    def production_revision(commit)
      original = ENV["RENDER_GIT_COMMIT"]
      ENV["RENDER_GIT_COMMIT"] = commit
      EnvironmentConfig.load("production").x.revision
    ensure
      ENV["RENDER_GIT_COMMIT"] = original
    end
end
