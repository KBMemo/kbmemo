# frozen_string_literal: true

module AgentChat
  # /agent_chat から渡される画像添付（Nyoy analyze_image 向け）。
  class ImageAttachments
    Attachment = Struct.new(:tsuzura_media_id, :filename, keyword_init: true)

    ULID_PATTERN = /\A[0-9A-HJKMNP-TV-Z]{26}\z/

    def self.normalize(raw)
      Array(raw).filter_map do |entry|
        if entry.is_a?(Attachment)
          entry
        elsif entry.is_a?(Hash) || entry.is_a?(ActionController::Parameters)
          hash = entry.is_a?(ActionController::Parameters) ? entry.to_unsafe_h : entry
          id = hash[:tsuzura_media_id].presence || hash["tsuzura_media_id"].presence
          id = id.to_s.strip.upcase
          next unless id.match?(ULID_PATTERN)

          filename = (hash[:filename].presence || hash["filename"].presence).to_s.strip.presence
          Attachment.new(tsuzura_media_id: id, filename: filename)
        end
      end
    end

    def self.as_json(attachments)
      Array(attachments).map do |attachment|
        {
          tsuzura_media_id: attachment.tsuzura_media_id,
          filename: attachment.filename
        }.compact
      end
    end
  end
end
