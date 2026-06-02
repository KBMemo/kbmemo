# frozen_string_literal: true

require "test_helper"

module Tsuzura
  class MediaUrlSignerTest < ActiveSupport::TestCase
    test "production defaults public url when env is unset" do
      with_env("TSUZURA_PUBLIC_URL" => nil) do
        Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
          assert_equal "https://media.kbmemo.net", MediaUrlSigner.base_url
        end
      end
    end

    test "development defaults to localhost when env is unset" do
      with_env("TSUZURA_PUBLIC_URL" => nil) do
        assert_equal "http://localhost:3008", MediaUrlSigner.base_url
      end
    end

    test "prefers TSUZURA_PUBLIC_URL over production default" do
      with_env("TSUZURA_PUBLIC_URL" => "https://cdn.example.test/") do
        Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
          assert_equal "https://cdn.example.test", MediaUrlSigner.base_url
        end
      end
    end

    private

    def with_env(overrides)
      previous = overrides.keys.index_with { |key| ENV[key] }
      overrides.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
