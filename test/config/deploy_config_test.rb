# frozen_string_literal: true

require "test_helper"
require "erb"
require "yaml"

class DeployConfigTest < ActiveSupport::TestCase
  REQUIRED_SECRETS = %w[
    RAILS_MASTER_KEY PRIMARY_DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL
    GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET DISCORD_CLIENT_ID DISCORD_CLIENT_SECRET
    SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USER_NAME SMTP_PASSWORD
  ].freeze

  def with_env(vars)
    previous = vars.keys.index_with { |key| ENV.fetch(key, nil) }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def deploy_config
    YAML.safe_load(ERB.new(Rails.root.join("config/deploy.yml").read).result)
  end

  test "deploy.yml renders the host and domain from ENV" do
    config = with_env("GS_VPS_HOST" => "198.51.100.7", "GS_DOMAIN" => "gs.example.test") { deploy_config }

    assert_equal "grindin-station", config["service"]
    assert_equal "ghcr.io/kakahpt/grindin-station", "#{config.dig('registry', 'server')}/#{config['image']}"
    assert_equal ["198.51.100.7"], config.dig("servers", "web")
    assert_equal "gs.example.test", config.dig("proxy", "host")
    assert_equal "gs.example.test", config.dig("env", "clear", "GS_DOMAIN")
    assert config.dig("proxy", "ssl")
    assert_equal "/up", config.dig("proxy", "healthcheck", "path")
    assert_equal "ghcr.io", config.dig("registry", "server")
    assert_equal "kakahpt", config.dig("registry", "username")
    assert_equal ["KAMAL_REGISTRY_PASSWORD"], config.dig("registry", "password")
    assert_equal "198.51.100.7", config.dig("accessories", "db", "host")
  end

  test "deploy.yml parses without ENV using documentation defaults" do
    config = with_env("GS_VPS_HOST" => nil, "GS_DOMAIN" => nil) { deploy_config }

    assert_equal ["203.0.113.10"], config.dig("servers", "web")
    assert_predicate config.dig("proxy", "host"), :present?
  end

  test "app env, volume and the Postgres accessory are configured" do
    config = deploy_config

    assert_equal REQUIRED_SECRETS.sort, config.dig("env", "secret").sort
    assert_equal true, config.dig("env", "clear", "SOLID_QUEUE_IN_PUMA")
    assert_equal "info", config.dig("env", "clear", "RAILS_LOG_LEVEL")
    assert_includes config["volumes"], "grindin_storage:/rails/storage"

    db = config.dig("accessories", "db")
    assert_equal "postgis/postgis:17-3.5", db["image"]
    assert_equal ["POSTGRES_PASSWORD"], db.dig("env", "secret")
    assert_includes db["directories"], "data:/var/lib/postgresql/data"
    assert_includes db["files"], "config/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql"
    assert_match(/\A127\.0\.0\.1:/, db["port"].to_s, "Postgres must not be exposed publicly")
  end

  test ".kamal/secrets defines every secret deploy.yml references and reads only from ENV" do
    config = deploy_config
    secrets = Rails.root.join(".kamal/secrets").read
    defined = secrets.scan(/^([A-Z][A-Z0-9_]*)=/).flatten

    referenced = config.dig("env", "secret") + config.dig("registry", "password") +
                 config.dig("accessories", "db", "env", "secret")
    assert_empty referenced - defined, "missing in .kamal/secrets"
    assert_no_match(/master\.key/, secrets)
  end

  test "init.sql creates the four production databases with the needed extensions" do
    sql = Rails.root.join("config/postgres/init.sql").read

    %w[grindin_station_production grindin_station_production_cache
       grindin_station_production_queue grindin_station_production_cable].each do |name|
      assert_match(/CREATE DATABASE #{name}\b/, sql)
    end
    assert_match(/CREATE EXTENSION IF NOT EXISTS postgis/, sql)
    assert_equal 4, sql.scan("CREATE EXTENSION IF NOT EXISTS pgcrypto").size
  end

  test "the deploy workflow only runs after a green CI on main and checks secrets first" do
    workflow = YAML.safe_load(Rails.root.join(".github/workflows/deploy.yml").read)
    trigger = workflow["on"] || workflow[true]

    assert_equal ["CI"], trigger.dig("workflow_run", "workflows")
    assert_equal ["main"], trigger.dig("workflow_run", "branches")
    assert_equal({ "group" => "deploy", "cancel-in-progress" => false }, workflow["concurrency"])

    job = workflow["jobs"]["deploy"]
    assert_match(/workflow_run\.conclusion == 'success'/, job["if"])
    names = job["steps"].pluck("name")
    assert_operator names.index("Check required secrets"), :<, names.index("Deploy with Kamal")
  end
end
