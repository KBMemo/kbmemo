# frozen_string_literal: true

require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  class FakeRodauth
    attr_reader :account

    def initialize(account)
      @account = account
    end

    def logged_in?
      account.present?
    end

    def rails_account
      account
    end
  end

  test "rejects when not authenticated" do
    assert_reject_connection { connect }
  end

  test "connects when rodauth is in env" do
    account = accounts(:one)
    connect env: { "rodauth" => FakeRodauth.new(account) }

    assert_equal account, connection.current_account
  end
end
