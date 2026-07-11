# frozen_string_literal: true

require "test_helper"

module Chat
  class ServerHealthTest < ActiveSupport::TestCase
    test "check_all uses role_overrides from form instead of account" do
      account = accounts(:one)
      account.update_chat_server_settings!(
        "roles" => {
          "intent" => { "base_url" => "http://saved.test:10010", "model" => "saved-model" }
        }
      )

      fake_http = Object.new
      fake_http.define_singleton_method(:use_ssl=) { |_| }
      fake_http.define_singleton_method(:open_timeout=) { |_| }
      fake_http.define_singleton_method(:read_timeout=) { |_| }
      fake_http.define_singleton_method(:get) do |_uri|
        response = Object.new
        response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
        response.define_singleton_method(:code) { "200" }
        response
      end

      Net::HTTP.stub(:new, fake_http) do
        results = ServerHealth.check_all(
          account: account,
          role_overrides: {
            "roles" => {
              "intent" => { "base_url" => "http://form.test:10010", "model" => "form-model" }
            }
          }
        )

        intent = results.find { |result| result.role == :intent }
        assert_equal "http://form.test:10010", intent.base_url
        assert_equal "form-model", intent.model
        assert intent.ok
      end
    end

    test "check_all treats blank form url as unset when override present" do
      account = accounts(:one)
      account.update_chat_server_settings!(
        "roles" => {
          "intent" => { "base_url" => "http://saved.test:10010", "model" => "saved-model" }
        }
      )

      results = ServerHealth.check_all(
        account: account,
        role_overrides: {
          "roles" => {
            "intent" => { "base_url" => "", "model" => "" }
          }
        }
      )

      intent = results.find { |result| result.role == :intent }
      assert_equal "未設定", intent.message
      assert_not intent.ok
    end
  end
end
