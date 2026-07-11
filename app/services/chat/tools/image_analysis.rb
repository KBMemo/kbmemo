# frozen_string_literal: true

require "base64"

module Chat
  module Tools
    # 徒然内画像解析: Tsuzura から画像を取得し、:vision モデルで説明する。
    class ImageAnalysis
      class Error < StandardError; end

      Result = Struct.new(:tsuzura_media_id, :description, :context_text, keyword_init: true)

      def initialize(account:, cookie_header: nil, vision_client: nil, media_fetcher: AgentChat::TsuzuraMediaFile)
        @account = account
        @cookie_header = cookie_header.to_s
        @vision_client = vision_client
        @media_fetcher = media_fetcher
      end

      def call(user_text:, image_attachments:)
        attachments = AgentChat::ImageAttachments.normalize(image_attachments)
        media_id = attachments.first&.tsuzura_media_id
        raise Error, "画像 ID がありません。画像を添付するか、葛籠から選択してください。" if media_id.blank?

        file = @media_fetcher.fetch(media_id: media_id, cookie_header: @cookie_header)
        prompt = user_text.to_s.strip.presence || "この画像を説明してください"
        description = vision_client.chat(vision_messages(prompt, file))

        Result.new(
          tsuzura_media_id: media_id,
          description: description,
          context_text: format_context(media_id, description)
        )
      rescue AgentChat::TsuzuraMediaFile::Error => e
        raise Error, e.message
      end

      private

      def vision_client
        @vision_client || Chat::ModelRegistry.for(:vision, account: @account).build_client
      end

      def vision_messages(prompt, file)
        data_url = "data:#{file.content_type};base64,#{Base64.strict_encode64(file.bytes)}"
        [
          { role: "system", content: Chat::Prompts::VISION },
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              { type: "image_url", image_url: { url: data_url } }
            ]
          }
        ]
      end

      def format_context(media_id, description)
        "### 画像解析 (#{media_id})\n#{description}"
      end
    end
  end
end
