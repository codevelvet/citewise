require "test_helper"

class StorageConfigTest < ActiveSupport::TestCase
  R2_ENV = {
    "R2_ACCOUNT_ID" => "test-account", "R2_ACCESS_KEY_ID" => "test-key-id",
    "R2_SECRET_ACCESS_KEY" => "test-secret", "R2_BUCKET" => "test-bucket"
  }

  test "the r2 service is S3 against the account's R2 endpoint, configured from the environment" do
    r2 = with_env(R2_ENV) { storage.fetch("r2") }

    assert_equal "S3", r2["service"]
    assert_equal "https://test-account.r2.cloudflarestorage.com", r2["endpoint"]
    assert_equal "auto", r2["region"]
    assert_equal "test-key-id", r2["access_key_id"]
    assert_equal "test-secret", r2["secret_access_key"]
    assert_equal "test-bucket", r2["bucket"]
  end

  test "the r2 service only sends and checks the checksums an operation requires" do
    r2 = with_env(R2_ENV) { storage.fetch("r2") }

    assert_equal "when_required", r2["request_checksum_calculation"]
    assert_equal "when_required", r2["response_checksum_validation"]
  end

  test "storage.yml parses without any R2 variables" do
    r2 = with_env(R2_ENV.transform_values { nil }) { storage.fetch("r2") }

    assert_nil r2["bucket"]
  end

  test "production stores files on r2, development and test on disk" do
    assert_equal :r2, EnvironmentConfig.load("production").active_storage.service
    assert_equal :local, EnvironmentConfig.load("development").active_storage.service
    assert_equal :test, EnvironmentConfig.load("test").active_storage.service
  end

  private
    def storage
      ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/storage.yml"))
    end

    def with_env(values)
      original = values.keys.index_with { ENV[it] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      original.each { |key, value| ENV[key] = value }
    end
end
