# frozen_string_literal: true

module Tsuzura
  class Authorizer
    def initialize(memo:, viewer: nil)
      @memo = memo
      @viewer = viewer
    end

    def allowed?
      return false unless @memo&.persisted?

      MemoPolicy.new(@viewer, @memo).show?
    end

    def sign_media_url(media_id)
      return nil unless allowed?

      MediaUrlSigner.sign(media_id: media_id, memo_id: @memo.id)
    end

    def sign_media_urls(media_ids)
      return {} unless allowed?

      Array(media_ids).each_with_object({}) do |raw_id, urls|
        id = raw_id.to_s.strip.upcase
        next if id.blank?

        urls[id] = MediaUrlSigner.sign(media_id: id, memo_id: @memo.id)
      end
    end
  end
end
