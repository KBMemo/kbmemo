# frozen_string_literal: true

require "test_helper"

module AgentChat
  class ImageAttachmentsTest < ActiveSupport::TestCase
    test "normalize accepts Attachment structs" do
      attachment = ImageAttachments::Attachment.new(
        tsuzura_media_id: "01JABCDEFGHJKMNPQRSTVWXYZ0",
        filename: "photo.jpg"
      )

      normalized = ImageAttachments.normalize([ attachment ])

      assert_equal 1, normalized.size
      assert_equal attachment.tsuzura_media_id, normalized.first.tsuzura_media_id
    end
  end
end
