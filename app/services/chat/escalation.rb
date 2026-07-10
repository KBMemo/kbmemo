# frozen_string_literal: true

module Chat
  # 一次応答モデルの結果を main へ昇格すべきか判定する（dev note §5）。
  # main が fast_chat と同一モデル・接続先のときは二重呼び出しになるため昇格しない。
  module Escalation
    CONFIDENCE_THRESHOLD = 0.7
    TOP_ROLE = :main

    # ユーザーが明示的に踏み込んだ回答を求めている合図。
    REQUEST_KEYWORDS = %w[詳しく 詳細 設計 仕様 仕様書 実装].freeze

    # 一次応答に「不明」系が多いと判断するしきい値。
    UNKNOWN_MARKERS = [ "不明", "わかりません", "判断できません", "情報がありません" ].freeze
    UNKNOWN_MARKER_LIMIT = 2

    # @param intent [Chat::IntentClassifier::Result]
    # @param user_text [String]
    # @param model_role [Symbol] 一次応答に使った役割
    # @param reply [String, nil] 一次応答本文（あれば内容も判定に使う）
    # @return [Boolean]
    def self.escalate?(intent:, user_text:, model_role:, reply: nil, account: nil)
      return false if model_role == TOP_ROLE
      return false if same_as_top_role?(model_role, account: account)

      return true if intent.confidence < CONFIDENCE_THRESHOLD
      return true if intent.intent.to_s == "code"
      return true if request_keyword?(user_text)
      return true if reply && unknown_heavy?(reply)

      false
    end

    def self.request_keyword?(user_text)
      text = user_text.to_s
      REQUEST_KEYWORDS.any? { |kw| text.include?(kw) }
    end

    def self.unknown_heavy?(reply)
      text = reply.to_s
      count = UNKNOWN_MARKERS.sum { |marker| text.scan(marker).size }
      count >= UNKNOWN_MARKER_LIMIT
    end

    def self.same_as_top_role?(model_role, account: nil)
      top = Chat::ModelRegistry.for(TOP_ROLE, account: account)
      current = Chat::ModelRegistry.for(model_role, account: account)
      top.base_url == current.base_url && top.model == current.model
    rescue KeyError
      false
    end
  end
end
