# frozen_string_literal: true

require "test_helper"

module Admin
  class AccountsControllerTest < ActionDispatch::IntegrationTest
    test "non-admin is redirected from admin" do
      sign_in_as(:two)
      get admin_accounts_url
      assert_redirected_to root_path
    end

    test "admin can list accounts" do
      sign_in_as(:one)
      get admin_accounts_url
      assert_response :success
    end

    test "admin can open account show" do
      sign_in_as(:one)
      get admin_account_url(accounts(:two))
      assert_response :success
    end
  end
end
