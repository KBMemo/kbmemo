# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/ordered_options"
require "minitest/autorun"
require_relative "../../config/db_credentials"

class DbCredentialsTest < Minitest::Test
  def test_connection_options_reads_env_specific_credentials
    credentials = stub_credentials(
      test: {
        host: "db.example.com",
        port: 5432,
        username: "kbmemo",
        password: "secret",
        database: "kbmemo_test"
      }
    )

    opts = DbCredentials.connection_options(:test, credentials: credentials)
    assert_equal "db.example.com", opts[:host]
    assert_equal 5432, opts[:port]
    assert_equal "kbmemo", opts[:username]
    assert_equal "secret", opts[:password]
  end

  def test_fetch_raises_when_key_missing
    credentials = stub_credentials(test: { host: "localhost" })

    assert_raises(KeyError) { DbCredentials.fetch(:database, :test, credentials: credentials) }
  end

  def test_config_raises_when_env_section_missing
    credentials = ActiveSupport::OrderedOptions.new

    error = assert_raises(KeyError) { DbCredentials.config(:development, credentials: credentials) }
    assert_match(/db\.development/, error.message)
  end

  private

  def stub_credentials(sections)
    db = ActiveSupport::OrderedOptions.new
    sections.each { |env, values| db[env] = values }
    creds = ActiveSupport::OrderedOptions.new
    creds[:db] = db
    creds
  end
end
