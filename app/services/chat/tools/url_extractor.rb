# frozen_string_literal: true

module Chat
  module Tools
    module UrlExtractor
      URL_PATTERN = %r{https?://[^\s<>"')\]]+}i

      module_function

      def first(text)
        match = text.to_s.match(URL_PATTERN)
        return nil unless match

        match.to_s.chomp(".,;)")
      end
    end
  end
end
