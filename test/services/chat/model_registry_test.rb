# frozen_string_literal: true

require "test_helper"

module Chat
  class ModelRegistryTest < ActiveSupport::TestCase
    setup { Chat::ModelRegistry.reset! }
    teardown { Chat::ModelRegistry.reset! }

    test "for resolves role to provider/model/temperature from config" do
      config = Chat::ModelRegistry.for(:main)

      assert_equal :main, config.role
      assert_equal :llama_cpp, config.provider
      assert_equal "gemma-4-12b", config.model
      assert_equal 0.5, config.temperature
    end

    test "for uses dev default base_url in test env when credentials absent" do
      assert_equal "http://localhost:10010", Chat::ModelRegistry.for(:main).base_url
      assert_equal "http://localhost:10031", Chat::ModelRegistry.for(:intent).base_url
    end

    test "for raises on unknown role" do
      assert_raises(KeyError) { Chat::ModelRegistry.for(:nope) }
    end

    test "build_client returns an OpenAI-compatible client for llama_cpp" do
      client = Chat::ModelRegistry.for(:fast_chat).build_client
      assert_instance_of Chat::LlmClient, client
    end

    test "build_client rejects non chat providers" do
      assert_raises(ArgumentError) { Chat::ModelRegistry.for(:image_generation).build_client }
    end

    test "embedding role resolves to embedding client" do
      config = Chat::ModelRegistry.for(:embedding)
      assert_equal "http://localhost:10034", config.base_url
      assert_instance_of Chat::EmbeddingClient, config.build_embedding_client
    end
  end
end
