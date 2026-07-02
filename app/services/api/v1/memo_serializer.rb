# frozen_string_literal: true

module Api
  module V1
    class MemoSerializer
      DEFAULT_FIELDS = %w[
        id uid slug title body body_format tags visibility properties
        created_at updated_at file_committed_at draft url
      ].freeze

      SUMMARY_FIELDS = %w[id uid title snippet tags updated_at draft url].freeze
      SNIPPET_LENGTH = 200

      def initialize(memo, fields: nil, summary: false, view_context:)
        @memo = memo
        @fields = normalize_fields(fields, summary: summary)
        @summary = summary
        @view_context = view_context
      end

      def as_json
        @fields.index_with { |field| send(:"field_#{field}") }.compact
      end

      private

      def normalize_fields(fields, summary:)
        allowed = summary ? SUMMARY_FIELDS : DEFAULT_FIELDS
        selected = Array(fields).map(&:to_s) & allowed
        selected.presence || allowed
      end

      def field_id
        @memo.id
      end

      def field_uid
        @memo.uid
      end

      def field_slug
        @memo.slug
      end

      def field_title
        @memo.title_unfilled? ? "" : @memo.title
      end

      def field_body
        @memo.body
      end

      def field_body_format
        "asciidoc"
      end

      def field_tags
        @memo.tags.map(&:name)
      end

      def field_visibility
        @memo.visibility
      end

      def field_properties
        @memo.properties
      end

      def field_created_at
        @memo.created_at.utc.iso8601
      end

      def field_updated_at
        @memo.updated_at.utc.iso8601
      end

      def field_file_committed_at
        @memo.file_committed_at&.utc&.iso8601
      end

      def field_draft
        @memo.file_committed_at.blank?
      end

      def field_url
        @view_context.memo_url(@memo)
      end

      def field_snippet
        body = @memo.body.to_s.gsub(/\s+/, " ").strip
        return "" if body.blank?

        body.length > SNIPPET_LENGTH ? "#{body[0, SNIPPET_LENGTH]}…" : body
      end
    end
  end
end
