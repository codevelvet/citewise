require "test_helper"
require "open3"

# config/application.rb reads RENDER_GIT_COMMIT at boot, so each case loads it in a fresh process.
class RevisionConfigTest < ActiveSupport::TestCase
  test "the revision is RENDER_GIT_COMMIT, shortened to seven characters" do
    assert_equal "0123abc", revision("RENDER_GIT_COMMIT" => "0123abcdef456789")
  end

  test "the revision is nil when RENDER_GIT_COMMIT is unset or empty" do
    assert_equal "nil", revision("RENDER_GIT_COMMIT" => nil)
    assert_equal "nil", revision("RENDER_GIT_COMMIT" => "")
  end

  private
    def revision(env)
      script = %(require "./config/application"; p Rails.configuration.x.revision)
      output, status = Open3.capture2e({ "RAILS_ENV" => "test" }.merge(env), RbConfig.ruby, "-e", script, chdir: Rails.root.to_s)
      assert status.success?, output
      output.lines.last.chomp.delete('"')
    end
end
