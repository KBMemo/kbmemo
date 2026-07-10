# frozen_string_literal: true

module Chat
  # llama-server 役割ごとの環境既定 URL（開発向け）。
  # balvenie 上の systemd サービス構成に合わせる。上書き: ENV CHAT_LLM_HOST / Account#chat_server_settings.base_urls。
  module ServerEndpoints
    ROLES = %i[intent fast_chat main vision embedding].freeze

    # chat-fast / chat-main（E4B）/ chat-reason（12B・任意）/ embedding / vlm のポート対応。
    DEFAULT_PORTS = {
      intent: 10_010,
      fast_chat: 10_011,
      main: 10_011,
      vision: 10_021,
      embedding: 10_020,
      image_generation: 11_234
    }.freeze

    ROLE_LABELS = {
      intent: "Intent（LFM2.5 1.2B）",
      fast_chat: "Fast chat（Gemma 4 E4B）",
      main: "Main（Gemma 4 E4B）",
      vision: "Vision（Qwen2.5-VL）",
      embedding: "Embedding（LFM2.5-Embedding-350M）",
      image_generation: "画像生成（sd.cpp）"
    }.freeze

    class << self
      def default_host
        ENV.fetch("CHAT_LLM_HOST", "http://balvenie").to_s.strip.chomp("/")
      end

      def url_for(host:, role:)
        port = DEFAULT_PORTS[role.to_sym]
        return nil unless port && host.present?

        "#{host}:#{port}"
      end

      def default_urls
        ROLES.index_with { |role| url_for(host: default_host, role: role) }
      end

      # 画面表示・フォーム初期値用。アカウント明示 URL がなければ環境既定。
      def resolved_urls(account: nil)
        defaults = default_urls
        return defaults unless account

        ROLES.index_with { |role| account.chat_server_base_url(role) || defaults[role] }
      end
    end
  end
end
