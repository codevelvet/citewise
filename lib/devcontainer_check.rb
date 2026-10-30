require "json"
require "strscan"

# Checks the dev container's security settings. Standard library only:
# CI runs bin/check-devcontainer without bundle install.
class DevcontainerCheck
  FORBIDDEN_KEYS = %w[privileged runArgs mounts initializeCommand].freeze
  APP_READ_ONLY_TARGETS = %w[.claude .github .devcontainer .git/hooks .git/config CLAUDE.md]
    .map { |path| "/workspaces/citewise/#{path}" }.freeze
  POSTGRES_READ_ONLY_TARGETS = %w[/docker-entrypoint-initdb.d /etc/postgresql/pg_hba.conf].freeze

  # VS Code accepts comments and trailing commas in devcontainer.json and drops
  # what it can't parse. Strip comments outside strings, then parse strict JSON.
  def self.parse_jsonc(text)
    scanner = StringScanner.new(text)
    json = +""
    until scanner.eos?
      if scanner.scan(/"(?:[^"\\]|\\.)*"/m)
        json << scanner.matched
      elsif scanner.scan(%r{//[^\n]*})
        # Drop the comment, keep the newline.
      elsif scanner.scan(%r{/\*.*?\*/}m)
        json << scanner.matched.gsub(/[^\n]/, " ")
      else
        json << scanner.getch
      end
    end
    JSON.parse(json)
  end

  def devcontainer_failures(text)
    config = self.class.parse_jsonc(text)
    failures = []

    failures << "overrideCommand must be false" unless config["overrideCommand"] == false

    Array(config["forwardPorts"]).each do |port|
      if port.to_s.split(":").last == "5432" || port.to_s.start_with?("postgres:")
        failures << "forwardPorts must not forward the database (#{port.inspect})"
      end
    end

    unless config.dig("customizations", "vscode", "settings", "remote.autoForwardPorts") == false
      failures << "customizations.vscode.settings remote.autoForwardPorts must be false"
    end

    failures << 'remoteEnv SSH_AUTH_SOCK must be ""' unless config.dig("remoteEnv", "SSH_AUTH_SOCK") == ""

    FORBIDDEN_KEYS.each { |key| failures << "#{key} must not be set" if config.key?(key) }

    failures.map { |failure| "devcontainer.json: #{failure}" }
  rescue JSON::ParserError => e
    [ "devcontainer.json: invalid JSON: #{e.message.split.join(" ")}" ]
  end

  # Checks the output of `docker compose -f .devcontainer/compose.yaml config --format json`.
  def compose_failures(text)
    compose = JSON.parse(text)
    services = compose["services"] || {}
    failures = []

    if (app = services["rails-app"])
      failures << "rails-app cap_add must be exactly NET_ADMIN and NET_RAW" unless Array(app["cap_add"]).sort == %w[NET_ADMIN NET_RAW]
      failures << "rails-app must not be privileged" if app["privileged"]
      failures << "rails-app may only publish port 3000 on 127.0.0.1" unless Array(app["ports"]).all? { |port| loopback_rails_port?(port) }
      failures << "rails-app must not have env_file" if app.key?("env_file")
      Array(app["volumes"]).each do |volume|
        failures << "rails-app must not mount a Docker socket (#{volume["source"]})" if volume["source"].to_s.include?("docker.sock")
      end
      failures.concat read_only_failures("rails-app", app, APP_READ_ONLY_TARGETS)
    else
      failures << "rails-app service is missing"
    end

    if (postgres = services["postgres"])
      failures << "postgres must not have ports" if postgres.key?("ports")
      failures.concat read_only_failures("postgres", postgres, POSTGRES_READ_ONLY_TARGETS)
    else
      failures << "postgres service is missing"
    end

    failures << "the database network must be external" unless compose.dig("networks", "database", "external") == true

    failures.map { |failure| "compose: #{failure}" }
  rescue JSON::ParserError => e
    [ "compose: invalid JSON: #{e.message.split.join(" ")}" ]
  end

  private
    # The Rails dev server on host loopback only. Without host_ip, Docker binds
    # every interface and the dev server (and web-console) is reachable from the LAN.
    def loopback_rails_port?(port)
      port.is_a?(Hash) &&
        port["host_ip"] == "127.0.0.1" &&
        port["target"].to_s == "3000" &&
        port["published"].to_s == "3000" &&
        port.fetch("protocol", "tcp") == "tcp"
    end

    def read_only_failures(name, service, targets)
      targets.filter_map do |target|
        binds = Array(service["volumes"]).select { |volume| volume["type"] == "bind" && volume["target"] == target }
        if binds.empty?
          "#{name} has no bind for #{target}"
        elsif !binds.all? { |bind| bind["read_only"] == true }
          "#{name} bind for #{target} must be read-only"
        end
      end
    end
end
