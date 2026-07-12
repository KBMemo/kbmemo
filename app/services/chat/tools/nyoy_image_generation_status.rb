# frozen_string_literal: true

module Chat
  module Tools
    # Nyoy MCP get_image_generation の応答を UI 向けに正規化する。
    module NyoyImageGenerationStatus
      TERMINAL_SUCCESS = (
        NyoyMcpRunner::IMAGE_GENERATION_COMPLETED +
        NyoyMcpRunner::IMAGE_GENERATION_AWAITING
      ).freeze
      TERMINAL_FAILED = NyoyMcpRunner::IMAGE_GENERATION_FAILED.freeze

      module_function

      def normalize(payload, client:)
        hash = payload.is_a?(Hash) ? payload : {}
        status = (hash["status"] || hash["state"]).to_s.downcase
        image_urls = collect_image_urls(hash, client: client)

        {
          id: hash["id"],
          status: status,
          status_label: hash["status_label"],
          image_urls: image_urls,
          show_url: absolute_nyoy_url(hash["show_path"], client: client),
          in_progress: in_progress?(status),
          done: terminal?(status),
          failed: status.in?(TERMINAL_FAILED),
          error_message: hash["error_message"]
        }.compact
      end

      def in_progress?(status)
        status.present? && !terminal?(status)
      end

      def terminal?(status)
        status.in?(TERMINAL_SUCCESS) || status.in?(TERMINAL_FAILED)
      end

      def collect_image_urls(payload, client:)
        urls = []
        Array(payload["draft_urls"]).each do |url|
          absolute = absolute_nyoy_url(url, client: client)
          urls << absolute if absolute.present?
        end

        primary = payload["image_url"].presence || payload["url"].presence
        urls << absolute_nyoy_url(primary, client: client) if primary.present?

        show_path = payload["show_path"].to_s.presence
        if urls.empty? && show_path.present? && terminal_success?(payload)
          absolute = absolute_nyoy_url(show_path, client: client)
          urls << absolute if absolute.present?
        end

        urls.uniq
      end

      def terminal_success?(payload)
        status = (payload["status"] || payload["state"]).to_s.downcase
        status.in?(TERMINAL_SUCCESS)
      end

      def absolute_nyoy_url(path, client:)
        path = path.to_s
        return path if path.match?(%r{\Ahttps?://}i)
        return nil if path.blank?

        origin = client.site_origin
        return nil if origin.blank?

        "#{origin}#{path.start_with?("/") ? path : "/#{path}"}"
      end
    end
  end
end
