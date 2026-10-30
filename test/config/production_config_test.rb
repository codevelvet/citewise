require "test_helper"

# Production's SSL and host settings, exercised through the real middleware without booting production.
class ProductionConfigTest < ActiveSupport::TestCase
  RENDER_HOST = "citewise-web.onrender.com"

  APP = ->(_env) { [ 200, { "set-cookie" => "session_id=abc; path=/; httponly" }, [ "ok" ] ] }

  test "production assumes and forces SSL" do
    config = EnvironmentConfig.load("production")

    assert_equal true, config.assume_ssl
    assert_equal true, config.force_ssl
  end

  test "the HTTPS redirect skips /up only" do
    ssl = ActionDispatch::SSL.new(APP, **EnvironmentConfig.load("production").ssl_options)

    assert_equal 200, ssl.call(request("http://#{RENDER_HOST}/up")).first
    status, headers, _ = ssl.call(request("http://#{RENDER_HOST}/session/new"))
    assert_equal 301, status
    assert_equal "https://#{RENDER_HOST}/session/new", headers["location"]
  end

  test "the session cookie is marked Secure behind Render's TLS-terminating proxy" do
    _, headers, _ = production_stack.call(request("http://#{RENDER_HOST}/session/new", "HTTP_X_FORWARDED_PROTO" => "https"))

    assert_match(/session_id=abc;.*\bsecure\b/i, Array(headers["set-cookie"]).join("\n"))
  end

  test "only Render's hostname is allowed, except on /up" do
    stack = production_stack

    assert_equal 200, stack.call(request("https://#{RENDER_HOST}/session/new")).first
    assert_equal 403, stack.call(request("https://evil.example/session/new")).first
    assert_equal 200, stack.call(request("http://10.0.0.5:10000/up")).first
  end

  test "every host is rejected when RENDER_EXTERNAL_HOSTNAME is unset" do
    stack = production_stack(hostname: nil)

    assert_equal 403, stack.call(request("https://#{RENDER_HOST}/session/new")).first
    assert_equal 200, stack.call(request("http://10.0.0.5:10000/up")).first
  end

  private
    # A browser's request: unlike Rack::MockRequest alone, it sends the Host header HostAuthorization checks.
    def request(url, headers = {})
      uri = URI(url)
      Rack::MockRequest.env_for(url, "HTTP_HOST" => uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}", **headers)
    end

    # The order Rails::Application::DefaultMiddlewareStack uses.
    def production_stack(hostname: RENDER_HOST)
      config = with_hostname(hostname) { EnvironmentConfig.load("production") }
      app = config.force_ssl == true ? ActionDispatch::SSL.new(APP, **config.ssl_options) : APP
      app = ActionDispatch::AssumeSSL.new(app) if config.assume_ssl
      ActionDispatch::HostAuthorization.new(app, config.hosts, **config.host_authorization)
    end

    def with_hostname(hostname)
      original = ENV["RENDER_EXTERNAL_HOSTNAME"]
      ENV["RENDER_EXTERNAL_HOSTNAME"] = hostname
      yield
    ensure
      ENV["RENDER_EXTERNAL_HOSTNAME"] = original
    end
end
