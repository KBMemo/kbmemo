# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class NyoyImageGenerationStatusTest < ActiveSupport::TestCase
      test "collects draft urls and marks awaiting selection as done" do
        client = Object.new
        client.define_singleton_method(:site_origin) { "https://nyoy.example" }

        normalized = NyoyImageGenerationStatus.normalize(
          {
            "id" => 42,
            "status" => "awaiting_selection",
            "draft_urls" => [ "https://nyoy.example/rails/active_storage/draft.png" ],
            "show_path" => "/image_generations/42"
          },
          client: client
        )

        assert normalized[:done]
        refute normalized[:failed]
        assert_equal [ "https://nyoy.example/rails/active_storage/draft.png" ], normalized[:image_urls]
      end
    end
  end
end
