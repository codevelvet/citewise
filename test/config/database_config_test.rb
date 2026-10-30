require "test_helper"

class DatabaseConfigTest < ActiveSupport::TestCase
  RENDER_URL = "postgresql://citewise:secret@dpg-example-a:5432/citewise_production?sslmode=require"

  test "production keeps cache, queue, and cable in their own databases on DATABASE_URL's instance" do
    configs = production_configs(RENDER_URL)

    assert_equal RENDER_URL, configs.fetch("primary").url
    %w[cache queue cable].each do |name|
      config = configs.fetch(name)
      assert_equal "postgresql://citewise:secret@dpg-example-a:5432/citewise_production_#{name}?sslmode=require", config.url
      assert_equal "db/#{name}_migrate", config.migrations_paths
    end
  end

  test "suffixing works on a URL without query parameters" do
    assert_equal "postgres://u:p@host/citewise_production_queue", production_configs("postgres://u:p@host/citewise_production").fetch("queue").url
  end

  private
    def production_configs(database_url)
      original = ENV["DATABASE_URL"]
      ENV["DATABASE_URL"] = database_url
      yaml = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/database.yml"))
      ActiveRecord::DatabaseConfigurations.new(yaml).configs_for(env_name: "production").index_by(&:name)
    ensure
      ENV["DATABASE_URL"] = original
    end
end
