# frozen_string_literal: true

require "active_support/core_ext/hash/keys"

# PostgreSQL 接続情報。正は Rails credentials の db.* 配下。
# テンプレート: config/credentials/db.example.yml
module DbCredentials
  class << self
    def config(env = Rails.env, credentials: Rails.application.credentials)
      cfg = credentials.dig(:db, env.to_sym)
      if cfg.blank?
        raise KeyError,
          "Missing credentials db.#{env} — add it with bin/rails credentials:edit " \
          "(see config/credentials/db.example.yml)"
      end

      normalize_section(cfg)
    end

    def fetch(key, env = Rails.env, credentials: Rails.application.credentials)
      value = config(env, credentials: credentials)[key.to_s]
      if value.nil? || value == ""
        raise KeyError,
          "Missing credentials db.#{env}.#{key} — see config/credentials/db.example.yml"
      end

      value
    end

    def connection_options(env = Rails.env, credentials: Rails.application.credentials)
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

    private :normalize_section
  end
end
