require "json"
require "strscan"

# Checks the dev container's security settings. Standard library only:
# CI runs bin/check-devcontainer without bundle install.
class DevcontainerCheck
  FORBIDDEN_KEYS = %w[privileged runArgs mounts initializeCommand].freeze

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
end
