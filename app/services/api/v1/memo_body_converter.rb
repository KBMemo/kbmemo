# frozen_string_literal: true

module Api
  module V1
    class MemoBodyConverter
      class Error < StandardError; end
      class UnsupportedFormat < Error; end

      FORMATS = %w[asciidoc markdown].freeze

      def self.normalize!(attributes)
        attrs = attributes.to_h.deep_symbolize_keys
        format = attrs.delete(:body_format).to_s.downcase.presence || "asciidoc"
        unless FORMATS.include?(format)
          raise UnsupportedFormat, "body_format は asciidoc または markdown です。"
        end

        return attrs if format == "asciidoc"

        attrs[:body] = convert!(attrs[:body]) if attrs.key?(:body)
        attrs[:append_body] = convert!(attrs[:append_body]) if attrs.key?(:append_body)
        attrs
      end

      def self.convert!(text)
        PandocMarkdownToAsciidoc.convert(text)
      rescue PandocRunner::NotFound, PandocRunner::Error => e
        raise Error, e.message
      end
    end
  end
end
