# frozen_string_literal: true

module Chat
  # intent を「使用モデル役割」と「必要ツール」へ振り分ける（dev note §2）。
  # ツールは Phase 3 以降で実装。ここでは名前を返すのみ。
  module Router
    Decision = Struct.new(:intent, :model_role, :tools, keyword_init: true)

    # role: ModelRegistry の役割 / tools: Chat::Tools の名前（Phase 3+ で実装）
    ROUTES = {
      "conversation" => { role: :fast_chat, tools: [] },
      "summarization" => { role: :fast_chat, tools: [] },
      "translation" => { role: :fast_chat, tools: [] },
      "url_analysis" => { role: :fast_chat, tools: %i[fetch_url] },
      "web_research" => { role: :main, tools: %i[web_search fetch_url] },
      "rag_lookup" => { role: :main, tools: %i[rag_search] },
      "code" => { role: :main, tools: [] },
      "image_analysis" => { role: :vision, tools: %i[image_analysis] },
      "image_generation" => { role: :image_generation, tools: %i[image_generation] },
      "memo_search" => { role: :main, tools: %i[memo_search] },
      "memo_add" => { role: :main, tools: %i[memo_add] },
      "settings_change" => { role: nil, tools: %i[settings_change] },
      "unknown" => { role: :fast_chat, tools: [] }
    }.freeze

    DEFAULT_ROUTE = { role: :fast_chat, tools: [] }.freeze

    # @param intent_result [Chat::IntentClassifier::Result]
    # @return [Chat::Router::Decision]
    def self.decide(intent_result)
      entry = ROUTES.fetch(intent_result.intent.to_s, DEFAULT_ROUTE)
      Decision.new(
        intent: intent_result.intent.to_s,
        model_role: entry[:role],
        tools: entry[:tools].dup
      )
    end
  end
end
