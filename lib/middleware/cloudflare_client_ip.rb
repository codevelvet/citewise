require "ipaddr"

# Behind Cloudflare (Render), REMOTE_ADDR is a Cloudflare edge, and X-Forwarded-For can't be
# trusted because Render appends to the client's value. Cloudflare overwrites True-Client-IP and
# CF-Connecting-IP with the visitor's address, so when config.x.trust_cloudflare_ip is on, this
# replaces what ActionDispatch::RemoteIp worked out. It must run after RemoteIp and before
# Rails::Rack::Logger. Off, or without a valid header, the request keeps Rails' own remote_ip.
class CloudflareClientIp
  HEADERS = %w[HTTP_TRUE_CLIENT_IP HTTP_CF_CONNECTING_IP]

  def initialize(app)
    @app = app
  end

  def call(env)
    if Rails.configuration.x.trust_cloudflare_ip && (ip = client_ip(env))
      env["action_dispatch.remote_ip"] = ip
    end
    @app.call(env)
  end

  private
    def client_ip(env)
      HEADERS.each do |header|
        ip = single_address(env[header])
        return ip if ip
      end
      nil
    end

    # IPAddr also parses CIDR ranges and IPv6 zone IDs, so rule those out first.
    def single_address(value)
      return if value.nil? || value.empty? || value.match?(%r{[,/%\s]})

      address = IPAddr.new(value)
      value if address.ipv4? || address.ipv6?
    rescue IPAddr::Error
      nil
    end
end
