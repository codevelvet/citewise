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

  test "passes the compose fixture" do
    assert_empty compose_failures { }
  end

  test "fails unless rails-app cap_add is exactly NET_ADMIN and NET_RAW" do
    [ %w[NET_ADMIN NET_RAW SYS_ADMIN], %w[NET_ADMIN], nil ].each do |cap_add|
      assert_equal [ "compose: rails-app cap_add must be exactly NET_ADMIN and NET_RAW" ],
        compose_failures { |compose| app(compose)["cap_add"] = cap_add }
    end
  end

  test "fails when rails-app is privileged" do
    assert_equal [ "compose: rails-app must not be privileged" ],
      compose_failures { |compose| app(compose)["privileged"] = true }
  end

  test "fails when rails-app has ports" do
    assert_equal [ "compose: rails-app must not have ports" ],
      compose_failures { |compose| app(compose)["ports"] = [ { "target" => 3000, "published" => "3000", "protocol" => "tcp" } ] }
  end

  test "fails when rails-app has env_file" do
    assert_equal [ "compose: rails-app must not have env_file" ],
      compose_failures { |compose| app(compose)["env_file"] = [ { "path" => "/HOST_WORKSPACE/citewise/.env", "required" => true } ] }
  end

  test "fails when rails-app mounts a Docker socket" do
    assert_equal [ "compose: rails-app must not mount a Docker socket (/var/run/docker.sock)" ],
      compose_failures { |compose| app(compose)["volumes"] << { "type" => "bind", "source" => "/var/run/docker.sock", "target" => "/var/run/docker.sock", "bind" => {} } }
  end

  DevcontainerCheck::APP_READ_ONLY_TARGETS.each do |target|
    test "fails unless the rails-app bind for #{target} is read-only" do
      assert_equal [ "compose: rails-app bind for #{target} must be read-only" ],
        compose_failures { |compose| bind(app(compose), target).delete("read_only") }
    end
  end

  test "fails when a rails-app read-only bind is missing" do
    assert_equal [ "compose: rails-app has no bind for /workspaces/citewise/.git/hooks" ],
      compose_failures { |compose| app(compose)["volumes"].delete(bind(app(compose), "/workspaces/citewise/.git/hooks")) }
  end

  test "fails when postgres has ports" do
    assert_equal [ "compose: postgres must not have ports" ],
      compose_failures { |compose| postgres(compose)["ports"] = [ { "target" => 5432, "published" => "5432", "protocol" => "tcp" } ] }
  end

  DevcontainerCheck::POSTGRES_READ_ONLY_TARGETS.each do |target|
    test "fails unless the postgres bind for #{target} is read-only" do
      assert_equal [ "compose: postgres bind for #{target} must be read-only" ],
        compose_failures { |compose| bind(postgres(compose), target)["read_only"] = false }
    end
  end

  test "fails when a postgres read-only bind is missing" do
    assert_equal [ "compose: postgres has no bind for /etc/postgresql/pg_hba.conf" ],
      compose_failures { |compose| postgres(compose)["volumes"].delete(bind(postgres(compose), "/etc/postgresql/pg_hba.conf")) }
  end

  test "fails unless the database network is external" do
    assert_equal [ "compose: the database network must be external" ],
      compose_failures { |compose| compose["networks"]["database"].delete("external") }
  end

  test "fails when a service is missing" do
    assert_equal [ "compose: rails-app service is missing" ],
      compose_failures { |compose| compose["services"].delete("rails-app") }
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

    def compose_failures
      compose = JSON.parse(file_fixture("devcontainer/compose.json").read)
      yield compose
      DevcontainerCheck.new.compose_failures(JSON.generate(compose))
    end

    def app(compose)
      compose["services"]["rails-app"]
    end

    def postgres(compose)
      compose["services"]["postgres"]
    end

    def bind(service, target)
      service["volumes"].find { |volume| volume["target"] == target } || flunk("no bind for #{target}")
    end
end
