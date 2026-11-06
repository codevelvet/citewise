require "test_helper"
require "open3"

# config/application.rb reads CITEWISE_TRUST_CLOUDFLARE_IP at boot, so each case loads it in a fresh process.
class TrustCloudflareIpConfigTest < ActiveSupport::TestCase
  test "trust_cloudflare_ip is on only when CITEWISE_TRUST_CLOUDFLARE_IP is true" do
    assert_equal "false", trust_cloudflare_ip(nil)
    assert_equal "false", trust_cloudflare_ip("")
    assert_equal "false", trust_cloudflare_ip("1")
    assert_equal "true", trust_cloudflare_ip("true")
  end

  test "it's off in tests" do
    assert_equal false, Rails.configuration.x.trust_cloudflare_ip
  end

  private
    def trust_cloudflare_ip(value)
      env = { "RAILS_ENV" => "production", "CITEWISE_TRUST_CLOUDFLARE_IP" => value }
      output, status = Open3.capture2e(env, RbConfig.ruby, "-e", %(require "./config/application"; puts Rails.configuration.x.trust_cloudflare_ip), chdir: Rails.root.to_s)
      assert status.success?, output
      output.lines.last.chomp
    end
end
