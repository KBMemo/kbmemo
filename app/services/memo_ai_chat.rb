# frozen_string_literal: true

# メモ編集 AI チャット（AsciiDoc 前提・メモ本文をコンテキストに含める）。
class MemoAiChat
  MAX_BODY_CHARS = 12_000
  MAX_HISTORY = 12

  def initialize(account:, memo:, messages:, selection: nil)
    @account = account
    @memo = memo
    @messages = Array(messages)
    @selection = selection.to_s.strip.presence
  end

  # @return [Hash] { reply: String }
  def call
    key = @account.openai_api_key
    raise OpenaiChatCompletion::Error, "OpenAI API キーが未設定です。" if key.blank?

    client = OpenaiChatCompletion.new(api_key: key)
    reply = client.call(build_openai_messages)
    { reply: reply }
  end

  private

  def build_openai_messages
    [ system_message ] + trimmed_history
  end

  def system_message
    parts = [
      "あなたは kbmemo のメモ執筆アシスタントです。",
      "ユーザーがメモ本文に貼り付けられるよう、返答は AsciiDoc のプレーン文字列のみにしてください（Markdown は使わない）。",
      "見出しは `=` レベル、リストは `.` または `*`、強調は `*bold*`、リンクは `https://…[表示名]` または Wiki リンク `[[メモタイトル]]` / `[[タイトル|表示名]]` を使ってください。",
      "コードブロックが必要なら `[source]` または四連バッククォートを使ってください。",
      "説明や前置きは最小限にし、依頼に対する本文案を中心に書いてください。"
    ]

    parts << ""
    parts << "現在のメモタイトル: #{@memo.title}"
    parts << "メモ本文（抜粋）:"
    parts << truncate_body(@memo.body.to_s)

    if @selection
      parts << ""
      parts << "ユーザーがエディタで選択している抜粋:"
      parts << @selection
    end

    { role: "system", content: parts.join("\n") }
  end

  def trimmed_history
    @messages.last(MAX_HISTORY).filter_map do |entry|
      role = entry[:role] || entry["role"]
      content = (entry[:content] || entry["content"]).to_s.strip
      next if content.blank?
      next unless %w[user assistant].include?(role.to_s)

      { role: role.to_s, content: content }
    end
  end

  def truncate_body(body)
    return "（空）" if body.blank?
    return body if body.length <= MAX_BODY_CHARS

    "#{body[0, MAX_BODY_CHARS]}\n\n…（以降 #{body.length - MAX_BODY_CHARS} 文字省略）"
  end
end
