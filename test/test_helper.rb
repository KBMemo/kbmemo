ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "fileutils"

# Vite Ruby's build mutex is process-local. Build once before Rails forks test
# workers so they never race while replacing the shared test manifest.
FileUtils.mkdir_p(Rails.root.join("tmp"))
File.open(Rails.root.join("tmp", "vite-test-build.lock"), "w") do |lock|
  lock.flock(File::LOCK_EX)
  raise "Vite test assets failed to build" unless ViteRuby.commands.build
end
ViteRuby.commands.manifest.refresh

unless Object.method_defined?(:stub)
  class Object
    def stub(name, replacement)
      singleton = singleton_class
      existed = singleton.method_defined?(name) ||
        singleton.private_method_defined?(name) ||
        singleton.protected_method_defined?(name)
      original = singleton.instance_method(name) if existed
      visibility =
        if singleton.private_method_defined?(name)
          :private
        elsif singleton.protected_method_defined?(name)
          :protected
        else
          :public
        end

      define_singleton_method(name) do |*args, **kwargs, &block|
        next replacement unless replacement.respond_to?(:call)

        kwargs.empty? ? replacement.call(*args, &block) : replacement.call(*args, **kwargs, &block)
      end

      yield
    ensure
      if existed
        singleton.define_method(name, original)
        singleton.__send__(visibility, name)
      else
        singleton.__send__(:remove_method, name) if singleton.method_defined?(name)
      end
    end
  end
end

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

    # フィクスチャの slug は stem のみ。テスト DB では global_slug（-{uid} 付き）に揃える。
    def normalize_memo_slug_fixtures!
      Memo.find_each do |memo|
        next if memo.slug.blank? || memo.uid.blank?

        target = Memo.global_slug_for(
          Memo.slug_stem(memo.slug, memo_id: memo.id, uid: memo.uid),
          memo.uid
        )
        memo.update_column(:slug, target) if memo.slug != target
      end
    end

    def memo_global_slug(stem, memo)
      Memo.global_slug_for(stem, memo.uid)
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
