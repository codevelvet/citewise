ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
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
  config.before_record { |interaction| interaction.request.headers.delete("Authorization") }
end

Dir[Rails.root.join("test/support/**/*.rb")].each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
