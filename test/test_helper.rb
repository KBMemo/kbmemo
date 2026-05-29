ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "fileutils"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Dependent fixtures must use explicit account_id when accounts.yml sets explicit ids
    # (YAML `account: one` resolves to identify(:one), not the row's primary key).
    fixtures :all

    # テストごとに独立した Git 作業ツリーを割り当て、テスト間・並列ワーカー間で
    # ファイル状態（draft/commit/アセット）が漏れるフレーキーを防ぐ。
    # config.x.memo_git_work_tree は boot 時に一度だけ算出されるため、ここで毎回差し替える。
    # MemoRepository は呼び出し時に config を読むので、この差し替えが効く（DB はトランザクションで
    # ロールバックされるが、作業ツリーのファイルはロールバックされないため明示的に分離する）。
    setup do
      @memo_git_work_tree = Rails.root.join("tmp", "memo_git_test", "t-#{SecureRandom.hex(8)}")
      FileUtils.mkdir_p(@memo_git_work_tree)
      Rails.application.config.x.memo_git_work_tree = @memo_git_work_tree.to_s
    end

    teardown do
      FileUtils.rm_rf(@memo_git_work_tree) if @memo_git_work_tree
    end

    setup { normalize_memo_slug_fixtures! }

    def with_stubbed_kroki(svg_body = '<svg xmlns="http://www.w3.org/2000/svg"/>')
      original = MemoDiagramRenderer.method(:render)
      MemoDiagramRenderer.singleton_class.define_method(:render) { |engine:, source:, **| svg_body }
      yield
    ensure
      MemoDiagramRenderer.singleton_class.define_method(:render, original)
    end

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
