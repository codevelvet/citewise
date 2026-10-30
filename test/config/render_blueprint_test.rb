require "test_helper"

class RenderBlueprintTest < ActiveSupport::TestCase
  SECRETS = %w[RAILS_MASTER_KEY ANTHROPIC_API_KEY VOYAGE_API_KEY R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET]

  # Anthropic keys, Voyage/MongoDB Atlas keys, Rails master keys and R2 secrets (hex), long tokens, and connection strings.
  SECRET_SHAPES = [ /sk-ant-/, /\A(pa|al)-/, /\h{32}/, /[A-Za-z0-9+\/_=-]{40}/, %r{\Apostgres(ql)?://} ]

  setup do
    @blueprint = YAML.load_file(Rails.root.join("render.yaml"))
    @services = @blueprint.fetch("services").index_by { it.fetch("name") }
  end

  test "a web service" do
    assert_equal %w[web], @services.values.map { it["type"] }.sort
  end

  test "neither service deploys automatically" do
    @services.each_value do |service|
      assert_equal "off", service["autoDeployTrigger"], service["name"]
      assert_not service.key?("autoDeploy"), "#{service["name"]} uses the deprecated autoDeploy"
    end
  end

  test "preview environments and service previews are off" do
    assert_equal "off", @blueprint.dig("previews", "generation")
    @services.each_value { assert_nil it.dig("previews", "generation"), it["name"] }
  end

  test "the web service is health-checked on /up and migrates once per deploy" do
    assert_equal "/up", web["healthCheckPath"]
    assert_equal "./bin/rails db:prepare", web["preDeployCommand"]
  end

  test "every secret is entered in the dashboard, on both services" do
    @services.each_value do |service|
      env_vars = service.fetch("envVars").index_by { it.fetch("key") }
      SECRETS.each do |key|
        assert_equal({ "key" => key, "sync" => false }, env_vars[key], "#{service["name"]} #{key}")
      end
    end
  end

  test "DATABASE_URL comes from the database" do
    @services.each_value do |service|
      database_url = service.fetch("envVars").find { it["key"] == "DATABASE_URL" }
      assert_equal({ "name" => "citewise-db", "property" => "connectionString" }, database_url["fromDatabase"], service["name"])
    end
  end

  test "no committed value looks like a secret" do
    values = @services.values.flat_map { it.fetch("envVars") }.filter_map { it["value"] }
    assert_not_empty values

    values.each do |value|
      SECRET_SHAPES.each { |shape| assert_no_match shape, value }
    end
    @services.values.flat_map { it.fetch("envVars") }.each { assert_not it.key?("generateValue"), it["key"] }
  end

  private
    def web = @services.values.find { it["type"] == "web" }
    def worker = @services.values.find { it["type"] == "worker" }
end
