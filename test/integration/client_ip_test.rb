require "test_helper"

# The whole middleware stack: what sessions.ip_address and the "Started ... for" log line record.
class ClientIpTest < ActionDispatch::IntegrationTest
  CLOUDFLARE_HEADERS = { "True-Client-IP" => "203.0.113.9", "CF-Connecting-IP" => "203.0.113.9", "X-Forwarded-For" => "198.51.100.1" }

  setup do
    Rails.configuration.x.ask_page[:rate_limit_store].clear
    @user = create_user
  end

  teardown { Rails.configuration.x.trust_cloudflare_ip = false }

  test "CloudflareClientIp runs after RemoteIp and before the request is logged" do
    middleware = Rails.application.middleware.map(&:klass)
    assert_equal middleware.index(ActionDispatch::RemoteIp) + 1, middleware.index(CloudflareClientIp)
    assert_operator middleware.index(CloudflareClientIp), :<, middleware.index(Rails::Rack::Logger)
  end

  test "with the flag on, the session and the log record True-Client-IP, not X-Forwarded-For" do
    Rails.configuration.x.trust_cloudflare_ip = true

    log = capture_log { sign_in CLOUDFLARE_HEADERS }

    assert_equal "203.0.113.9", @user.sessions.sole.ip_address
    assert_match %r{Started POST "/session" for 203\.0\.113\.9 }, log
  end

  test "with the flag off, the headers are ignored" do
    log = capture_log { sign_in CLOUDFLARE_HEADERS.except("X-Forwarded-For") }

    assert_equal "127.0.0.1", @user.sessions.sole.ip_address
    assert_match %r{Started POST "/session" for 127\.0\.0\.1 }, log
  end

  private
    def sign_in(headers)
      post session_path, params: { email_address: @user.email_address, password: PASSWORD }, headers: headers
      assert_redirected_to root_url
    end

    def capture_log
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      Rails.logger.broadcast_to(logger)
      yield
      io.string
    ensure
      Rails.logger.stop_broadcasting_to(logger)
    end
end
