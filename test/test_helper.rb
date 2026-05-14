ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Dependent fixtures must use explicit account_id when accounts.yml sets explicit ids
    # (YAML `account: one` resolves to identify(:one), not the row's primary key).
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

module RodauthIntegrationSignIn
  def sign_in_as(fixture_key = :one)
    account = accounts(fixture_key)
    post "/login", params: { email: account.email, password: "password" }
  end
end

class ActionDispatch::IntegrationTest
  include RodauthIntegrationSignIn

  setup { sign_in_as(:one) }
end
