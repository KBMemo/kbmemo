# frozen_string_literal: true

require "test_helper"

class Chat::MemoChunkerTest < ActiveSupport::TestCase
  test "splits long body into chunks under max chars" do
    body = ("paragraph one.\n\n" * 50).strip
    chunks = Chat::MemoChunker.chunk(title: "Title", body: body, max_chars: 200)

    assert chunks.all? { |c| c.length <= 200 }
    assert_includes chunks.first, "Title"
  end

  test "returns title and body when short" do
    chunks = Chat::MemoChunker.chunk(title: "T", body: "short body")
    assert_equal [ "T", "short body" ], chunks
  end
end
