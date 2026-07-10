# frozen_string_literal: true

require "test_helper"

class Chat::MemoChunkerTest < ActiveSupport::TestCase
  test "splits long body into chunks under max chars" do
    body = ("paragraph one.\n\n" * 50).strip
    chunks = Chat::MemoChunker.chunk(title: "Title", body: body, max_chars: 200)

    assert chunks.all? { |c| c.length <= 200 }
    assert_includes chunks.first, "Title"
  end

  test "default max chars stays within embedding server token budget" do
    assert_operator Chat::MemoChunker::DEFAULT_MAX_CHARS, :<=, 480
  end

  test "strips base64 image blobs before chunking" do
    body = "intro\n\nimage:data:image/svg+xml;base64,#{"A" * 2_000}\n\noutro"
    chunks = Chat::MemoChunker.chunk(title: "T", body: body, max_chars: 200)

    joined = chunks.join("\n")
    refute_includes joined, "AAAA"
    assert_includes joined, "[image]"
    assert_includes joined, "outro"
  end

  test "returns title and body when short" do
    chunks = Chat::MemoChunker.chunk(title: "T", body: "short body")
    assert_equal [ "T", "short body" ], chunks
  end
end
