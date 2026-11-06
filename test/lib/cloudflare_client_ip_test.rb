require "test_helper"

class CloudflareClientIpTest < ActiveSupport::TestCase
  RAILS_IP = "104.23.0.1"

  setup { Rails.configuration.x.trust_cloudflare_ip = true }
  teardown { Rails.configuration.x.trust_cloudflare_ip = false }

  test "True-Client-IP sets remote_ip" do
    assert_equal "203.0.113.9", remote_ip("HTTP_TRUE_CLIENT_IP" => "203.0.113.9", "HTTP_CF_CONNECTING_IP" => "203.0.113.10")
  end

  test "CF-Connecting-IP is used when True-Client-IP is absent or invalid" do
    assert_equal "203.0.113.10", remote_ip("HTTP_CF_CONNECTING_IP" => "203.0.113.10")
    assert_equal "203.0.113.10", remote_ip("HTTP_TRUE_CLIENT_IP" => "nope", "HTTP_CF_CONNECTING_IP" => "203.0.113.10")
  end

  test "IPv6 addresses are accepted" do
    assert_equal "2001:db8::1", remote_ip("HTTP_TRUE_CLIENT_IP" => "2001:db8::1")
  end

  test "invalid or multi-valued headers are ignored" do
    [ "", "nope", "1.2.3.4, 5.6.7.8", "1.2.3.4 5.6.7.8", "10.0.0.0/8", "fe80::1%eth0", "999.1.1.1", " 1.2.3.4" ].each do |value|
      assert_equal RAILS_IP, remote_ip("HTTP_TRUE_CLIENT_IP" => value, "HTTP_CF_CONNECTING_IP" => value), value.inspect
    end
  end

  test "with the flag off, both headers are ignored" do
    Rails.configuration.x.trust_cloudflare_ip = false

    assert_equal RAILS_IP, remote_ip("HTTP_TRUE_CLIENT_IP" => "203.0.113.9", "HTTP_CF_CONNECTING_IP" => "203.0.113.10")
  end

  private
    # RAILS_IP stands in for what ActionDispatch::RemoteIp worked out.
    def remote_ip(headers)
      env = Rack::MockRequest.env_for("/", headers).merge("action_dispatch.remote_ip" => RAILS_IP)
      CloudflareClientIp.new(->(env) { [ 200, {}, [] ] }).call(env)
      ActionDispatch::Request.new(env).remote_ip
    end
end
