# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class ImageAnalysisTest < ActiveSupport::TestCase
      test "call accepts normalized Attachment structs from agent" do
        ulid = "01JABCDEFGHJKMNPQRSTVWXYZ0"
        attachment = AgentChat::ImageAttachments::Attachment.new(
          tsuzura_media_id: ulid,
          filename: "photo.jpg"
        )
        file = Struct.new(:content_type, :bytes).new("image/jpeg", "fake-image-bytes")
        vision = Object.new
        vision.define_singleton_method(:chat) { |*_args| "a blue sky" }

        tool = ImageAnalysis.new(
          account: accounts(:one),
          vision_client: vision,
          media_fetcher: Class.new do
            define_singleton_method(:fetch) { |**| file }
          end
        )

        result = tool.call(user_text: "何が写っていますか？", image_attachments: [ attachment ])

        assert_equal ulid, result.tsuzura_media_id
        assert_includes result.context_text, "a blue sky"
      end
    end
  end
end
