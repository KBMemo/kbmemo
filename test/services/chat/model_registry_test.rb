# frozen_string_literal: true

require "test_helper"

module Chat
  class ModelRegistryTest < ActiveSupport::TestCase
    setup { Chat::ModelRegistry.reset! }
    teardown { Chat::ModelRegistry.reset! }

    test "for resolves role to provider/model/temperature from config" do
      config = Chat::ModelRegistry.for(:main, account: accounts(:one))

      assert_equal :main, config.role
      assert_equal :llama_cpp, config.provider
      assert_equal "gemma-4-e4b", config.model
      assert_equal 0.5, config.temperature
      assert_equal "http://localhost:10011", config.base_url
    end

    test "for uses account chat_server_settings for url and model" do
      account = accounts(:one)
      account.update_chat_server_settings!(
        "roles" => {
          "main" => { "base_url" => "http://custom.test:9999", "model" => "custom-model" }
        }
      )

      config = Chat::ModelRegistry.for(:main, account: account)
      assert_equal "http://custom.test:9999", config.base_url
      assert_equal "custom-model", config.model
    end

    test "for raises when base_url missing without account" do
      assert_raises(KeyError) { Chat::ModelRegistry.for(:main) }
    end

    test "for raises on unknown role" do
      assert_raises(KeyError) { Chat::ModelRegistry.for(:nope) }
    end

    test "build_client returns an OpenAI-compatible client for llama_cpp" do
      client = Chat::ModelRegistry.for(:fast_chat, account: accounts(:one)).build_client
      assert_instance_of Chat::LlmClient, client
    end

    test "build_client rejects non chat providers" do
      config = Chat::ModelRegistry::Config.new(
        role: :image_generation,
        provider: :sd_cpp,
        base_url: "http://sd.test:11234",
        model: "sd-model",
        temperature: nil,
        api_key: nil
      )
      assert_raises(ArgumentError) { config.build_client }
    end

    test "embedding role resolves to embedding client" do
      config = Chat::ModelRegistry.for(:embedding, account: accounts(:one))
      assert_equal "http://localhost:10020", config.base_url
      assert_instance_of Chat::EmbeddingClient, config.build_embedding_client
    end
  end
end
