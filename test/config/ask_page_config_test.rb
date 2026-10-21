require "test_helper"
require "open3"

# config/application.rb reads these at boot, so each case loads it in a fresh process.
class AskPageConfigTest < ActiveSupport::TestCase
  test "max_concurrent_asks defaults to 1 when CITEWISE_MAX_CONCURRENT_ASKS is unset or empty" do
    assert_equal "1", ask_page(:max_concurrent_asks, "CITEWISE_MAX_CONCURRENT_ASKS" => nil)
    assert_equal "1", ask_page(:max_concurrent_asks, "CITEWISE_MAX_CONCURRENT_ASKS" => "")
  end

  test "max_concurrent_asks reads CITEWISE_MAX_CONCURRENT_ASKS" do
    assert_equal "3", ask_page(:max_concurrent_asks, "CITEWISE_MAX_CONCURRENT_ASKS" => "3")
  end

  test "boot fails when CITEWISE_MAX_CONCURRENT_ASKS isn't a positive integer" do
    [ "0", "-1", "two", "1.5", " 2" ].each do |value|
      output, status = load_config("puts 1", "CITEWISE_MAX_CONCURRENT_ASKS" => value)
      assert_not status.success?, value
      assert_includes output, "CITEWISE_MAX_CONCURRENT_ASKS must be a positive integer, got #{value.inspect}"
    end
  end

  test "the ask page is off in production unless CITEWISE_ASK_PAGE_ENABLED is true" do
    assert_equal "false", ask_page(:enabled, "RAILS_ENV" => "production", "CITEWISE_ASK_PAGE_ENABLED" => nil)
    assert_equal "false", ask_page(:enabled, "RAILS_ENV" => "production", "CITEWISE_ASK_PAGE_ENABLED" => "1")
    assert_equal "true", ask_page(:enabled, "RAILS_ENV" => "production", "CITEWISE_ASK_PAGE_ENABLED" => "true")
  end

  test "the ask page is on in development and test" do
    assert_equal "true", ask_page(:enabled, "RAILS_ENV" => "development", "CITEWISE_ASK_PAGE_ENABLED" => nil)
    assert Rails.configuration.x.ask_page[:enabled]
  end

  private
    def ask_page(key, env)
      output, status = load_config("puts Rails.configuration.x.ask_page.fetch(#{key.inspect})", env)
      assert status.success?, output
      output.lines.last.chomp
    end

    def load_config(script, env)
      Open3.capture2e({ "RAILS_ENV" => "test" }.merge(env), RbConfig.ruby, "-e", %(require "./config/application"; #{script}), chdir: Rails.root.to_s)
    end
end
