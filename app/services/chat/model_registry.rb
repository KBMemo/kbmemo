# frozen_string_literal: true

module Chat
  # Chat エージェントの役割（intent / fast_chat / main / vision / image_generation）を、
  # 接続情報（provider / base_url / model / temperature / api_key）へ解決する薄いアクセサ。
  #
  # 役割マッピング: config/chat_models.yml（provider / temperature 等）
  # 接続先 URL・モデル: Account#chat_server_settings（または credentials chat_models.base_urls）
  module ModelRegistry
    ROLES = %i[intent fast_chat main vision embedding image_generation].freeze

    Config = Struct.new(:role, :provider, :base_url, :model, :temperature, :api_key, keyword_init: true) do
      def build_client(api_key: nil)
        unless %i[llama_cpp openai].include?(provider)
          raise ArgumentError, "provider #{provider.inspect} は Chat::LlmClient 非対応です。"
        end

        Chat::LlmClient.new(
          base_url: base_url,
          model: model,
          api_key: api_key || self.api_key,
          temperature: temperature
        )
      end

      def build_embedding_client
        raise ArgumentError, "provider #{provider.inspect} は Chat::EmbeddingClient 非対応です。" unless provider == :llama_cpp

        Chat::EmbeddingClient.new(base_url: base_url, model: model)
      end
    end

    class << self
      # @param role [Symbol, String]
      # @param account [Account, nil] アカウント別 chat_server_settings を優先
      # @return [Chat::ModelRegistry::Config]
      def for(role, account: nil)
        key = role.to_sym
        entry = roles_config[key]
        raise KeyError, "未知の chat model role: #{role.inspect}" if entry.nil?

        Config.new(
          role: key,
          provider: entry[:provider].to_s.to_sym,
          base_url: resolve_base_url(key, account: account),
          model: resolve_model(key, account: account),
          temperature: entry[:temperature],
          api_key: resolve_api_key(key)
        )
      end

      def searxng_url
        credentials&.dig(:searxng_url).presence
      end

      # テスト等でメモ化をクリアするため。
      def reset!
        @roles_config = nil
      end

      private

      def roles_config
        @roles_config ||= Rails.application.config_for(:chat_models).to_h
      end

      def resolve_base_url(role, account: nil)
        if account
          account_url = account.chat_server_base_url(role)
          return normalize(account_url) if account_url.present?
        end

        explicit = credentials&.dig(:base_urls, role).presence
        return normalize(explicit) if explicit

        raise KeyError, "chat model role #{role.inspect} の接続 URL が未設定です（Chat サーバー設定）。"
      end

      def resolve_model(role, account: nil)
        if account
          selected = account.chat_server_model(role)
          return selected if selected.present?
        end

        entry = roles_config[role]
        configured = entry[:model].to_s.presence if entry
        return configured if configured

        raise KeyError, "chat model role #{role.inspect} のモデルが未設定です（Chat サーバー設定）。"
      end

      def resolve_api_key(role)
        credentials&.dig(:api_keys, role).presence
      end

      def credentials
        Rails.application.credentials.chat_models
      end

      def normalize(url)
        url.to_s.strip.chomp("/")
      end
    end
  end
end
