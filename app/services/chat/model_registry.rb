# frozen_string_literal: true

module Chat
  # Chat エージェントの役割（intent / fast_chat / main / vision / image_generation）を、
  # 接続情報（provider / base_url / model / temperature / api_key）へ解決する薄いアクセサ。
  #
  # 役割マッピング: config/chat_models.yml（非機密）
  # 接続先・機密: Rails credentials（chat_models）
  module ModelRegistry
    ROLES = %i[intent fast_chat main vision image_generation].freeze

    # development / test で base_url が未設定のときの既定（dev note §6）。
    DEV_DEFAULT_BASE_URLS = {
      intent: "http://localhost:10031",
      fast_chat: "http://localhost:10032",
      main: "http://localhost:10010",
      vision: "http://localhost:10033",
      image_generation: "http://localhost:11234"
    }.freeze

    Config = Struct.new(:role, :provider, :base_url, :model, :temperature, :api_key, keyword_init: true) do
      # OpenAI 互換 provider（llama_cpp / openai）向けのクライアントを組み立てる。
      # @param api_key [String, nil] BYOK 等で呼び出し側から差し込む場合
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
    end

    class << self
      # @param role [Symbol, String]
      # @return [Chat::ModelRegistry::Config]
      def for(role)
        key = role.to_sym
        entry = roles_config[key]
        raise KeyError, "未知の chat model role: #{role.inspect}" if entry.nil?

        Config.new(
          role: key,
          provider: entry[:provider].to_s.to_sym,
          base_url: resolve_base_url(key),
          model: entry[:model],
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

      def resolve_base_url(role)
        explicit = credentials&.dig(:base_urls, role).presence
        return normalize(explicit) if explicit

        return normalize(DEV_DEFAULT_BASE_URLS[role]) if local_default? && DEV_DEFAULT_BASE_URLS[role]

        raise KeyError, "chat model role #{role.inspect} の base_url が未設定です（credentials chat_models.base_urls）。"
      end

      def resolve_api_key(role)
        credentials&.dig(:api_keys, role).presence
      end

      def credentials
        Rails.application.credentials.chat_models
      end

      def local_default?
        Rails.env.development? || Rails.env.test?
      end

      def normalize(url)
        url.to_s.strip.chomp("/")
      end
    end
  end
end
