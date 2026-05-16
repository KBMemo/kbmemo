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

    setup { normalize_memo_slug_fixtures! }

    # フィクスチャの slug は stem のみ。テスト DB では global_slug（-{id} 付き）に揃える。
    def normalize_memo_slug_fixtures!
      Memo.find_each do |memo|
        next if memo.slug.blank?

        target = Memo.global_slug_for(Memo.slug_stem(memo.slug, memo_id: memo.id), memo.id)
        memo.update_column(:slug, target) if memo.slug != target
      end
    end
  end
end

module RodauthIntegrationSignIn
  def sign_in_as(fixture_key = :one)
    account = accounts(fixture_key)
    post "/login", params: { email: account.email, password: "password" }
  end

  def sign_out
    post "/logout"
  end
end

class ActionDispatch::IntegrationTest
  include RodauthIntegrationSignIn

  setup { sign_in_as(:one) }
end
