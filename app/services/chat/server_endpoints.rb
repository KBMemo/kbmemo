# frozen_string_literal: true

module Chat
  # Chat エージェントの役割一覧（接続先は Account#chat_server_settings に保存）。
  module ServerEndpoints
    ROLES = %i[intent fast_chat main vision embedding].freeze

    ROLE_LABELS = {
      intent: "Intent",
      fast_chat: "Fast chat",
      main: "Main",
      vision: "Vision",
      embedding: "Embedding"
    }.freeze
  end
end
