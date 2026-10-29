ENV["RAILS_ENV"] ||= "test"
# Tests never need real keys, so failure messages that echo request headers
# can't leak them. Recording keeps the real keys: filter_sensitive_data needs
# them to know what to scrub. Set before boot, which configures the clients.
unless ENV["VCR_RECORD"]
  ENV["ANTHROPIC_API_KEY"] = "test-anthropic-key"
  ENV["VOYAGE_API_KEY"] = "test-voyage-key"
end
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require "webmock/minitest"
require "vcr"

# Tests never touch the network. Stub requests with WebMock or replay a VCR cassette.
WebMock.disable_net_connect!

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("test/vcr_cassettes")
  config.hook_into :webmock
  # Replay only. Recording spends API credit, so it takes an explicit VCR_RECORD=1.
  config.default_cassette_options = { record: ENV["VCR_RECORD"] ? :once : :none }
  config.filter_sensitive_data("<VOYAGE_API_KEY>") { ENV["VOYAGE_API_KEY"] }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  # Voyage authenticates with Authorization, Anthropic with X-Api-Key. Anthropic's
  # responses also name the account's organization and workspace.
  config.before_record do |interaction|
    interaction.request.headers.reject! { |name, _| name.casecmp?("Authorization") || name.casecmp?("X-Api-Key") }
    interaction.response.headers.reject! { |name, _| name.casecmp?("Anthropic-Organization-Id") || name.casecmp?("Anthropic-Workspace-Id") }
  end
end

Dir[Rails.root.join("test/support/**/*.rb")].each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Add more helper methods to be used by all tests here...
    include UserTestHelper
  end
end
