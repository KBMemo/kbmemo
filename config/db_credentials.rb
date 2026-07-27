# frozen_string_literal: true

require "active_support/core_ext/hash/keys"

# PostgreSQL 接続情報。正は Rails credentials の db.* 配下。
# テンプレート: config/credentials/db.example.yml
module DbCredentials
  class << self
    def config(env = Rails.env, credentials: nil)
      use_ci_config = credentials.nil? && ci_config?
      credentials ||= Rails.application.credentials
      return ci_config if use_ci_config

      cfg = credentials.dig(:db, env.to_sym)
      if cfg.blank?
        raise KeyError,
          "Missing credentials db.#{env} — add it with bin/rails credentials:edit " \
          "(see config/credentials/db.example.yml)"
      end

      normalize_section(cfg)
    end

    def fetch(key, env = Rails.env, credentials: nil)
      value = config(env, credentials: credentials)[key.to_s]
      if value.nil? || value == ""
        raise KeyError,
          "Missing credentials db.#{env}.#{key} — see config/credentials/db.example.yml"
      end

      value
    end

    def connection_options(env = Rails.env, credentials: nil)
      {
        host: fetch(:host, env, credentials: credentials),
        port: fetch(:port, env, credentials: credentials),
        username: fetch(:username, env, credentials: credentials),
        password: fetch(:password, env, credentials: credentials)
      }
    end

    def normalize_section(cfg)
      (cfg.is_a?(Hash) ? cfg : cfg.to_h).stringify_keys
    end

    def ci_config?
      ENV["KBMEMO_CI_DB_HOST"].present?
    end

    def ci_config
      database = ENV.fetch("KBMEMO_CI_DB_DATABASE")

      {
        "host" => ENV.fetch("KBMEMO_CI_DB_HOST"),
        "port" => ENV.fetch("KBMEMO_CI_DB_PORT", "5432"),
        "username" => ENV.fetch("KBMEMO_CI_DB_USERNAME"),
        "password" => ENV.fetch("KBMEMO_CI_DB_PASSWORD"),
        "database" => database,
        "cache_database" => database,
        "queue_database" => database,
        "cable_database" => database
      }
    end

    private :normalize_section, :ci_config?, :ci_config
  end
end
