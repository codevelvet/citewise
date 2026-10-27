require "test_helper"

class DevcontainerCheckTest < ActiveSupport::TestCase
  test "passes the devcontainer.json fixture" do
    assert_empty DevcontainerCheck.new.devcontainer_failures(devcontainer)
  end

  test "keeps // and /* inside strings" do
    config = DevcontainerCheck.parse_jsonc(devcontainer)
    assert_includes config["postAttachCommand"], "https://example.com"

    config = DevcontainerCheck.parse_jsonc(%q({"a": "x \" // y", "b": "/* z */"} // comment))
    assert_equal({ "a" => 'x " // y', "b" => "/* z */" }, config)
  end

  test "fails on a missing comma" do
    assert_invalid_json devcontainer_failures(%("service": "rails-app",), %("service": "rails-app"))
  end

  test "fails on a trailing comma" do
    assert_invalid_json devcontainer_failures(%("SSH_AUTH_SOCK": ""), %("SSH_AUTH_SOCK": "",))
  end

  test "fails on an unterminated block comment" do
    assert_invalid_json devcontainer_failures("     which starts the firewall and runs the security checks. */", "")
  end

  test "fails unless overrideCommand is false" do
    assert_equal [ "devcontainer.json: overrideCommand must be false" ],
      devcontainer_failures(%("overrideCommand": false), %("overrideCommand": true))
    assert_equal [ "devcontainer.json: overrideCommand must be false" ],
      devcontainer_failures(%("overrideCommand": false,), "")
  end

  [ "5432", %("5432"), %("localhost:5432"), %("postgres:5433") ].each do |port|
    test "fails when forwardPorts has #{port}" do
      assert_equal [ "devcontainer.json: forwardPorts must not forward the database (#{port})" ],
        devcontainer_failures(%("forwardPorts": [3000]), %("forwardPorts": [3000, #{port}]))
    end
  end

  test "fails unless remote.autoForwardPorts is false" do
    assert_equal [ "devcontainer.json: customizations.vscode.settings remote.autoForwardPorts must be false" ],
      devcontainer_failures(%("remote.autoForwardPorts": false), %("remote.autoForwardPorts": true))
  end

  test "fails unless remoteEnv SSH_AUTH_SOCK is empty" do
    assert_equal [ 'devcontainer.json: remoteEnv SSH_AUTH_SOCK must be ""' ],
      devcontainer_failures(%("SSH_AUTH_SOCK": ""), %("SSH_AUTH_SOCK": "${localEnv:SSH_AUTH_SOCK}"))
    assert_equal [ 'devcontainer.json: remoteEnv SSH_AUTH_SOCK must be ""' ],
      devcontainer_failures(%("SSH_AUTH_SOCK": ""), "")
  end

  { "privileged" => "true", "runArgs" => %(["--privileged"]), "mounts" => "[]", "initializeCommand" => %("echo hi") }.each do |key, value|
    test "fails when #{key} is set" do
      assert_equal [ "devcontainer.json: #{key} must not be set" ],
        devcontainer_failures(%("name": "citewise",), %("name": "citewise", "#{key}": #{value},))
    end
  end

  private
    def devcontainer
      file_fixture("devcontainer/devcontainer.json").read
    end

    def devcontainer_failures(from, to)
      text = devcontainer
      assert_includes text, from
      DevcontainerCheck.new.devcontainer_failures(text.sub(from, to))
    end

    def assert_invalid_json(failures)
      assert_equal 1, failures.size, failures.inspect
      assert_match(/\Adevcontainer\.json: invalid JSON: .+ at line \d+ column \d+\z/, failures.first)
    end
end
