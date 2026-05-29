# frozen_string_literal: true

module KbmemoAsciidocSamples
  # 公式 Syntax Quick Reference フィクスチャ由来の記法サンプルメモを、
  # 「AsciiDoc カバレッジ」ノートブックへ冪等に upsert する開発用シード。
  #
  # - 1 syntax-ref id = 1 メモ（タイトル = id、本文 = `= id` + フィクスチャ断片）。
  # - 既存の手動サンプルは properties マーカー or タイトル別名で同定し、タイトルを id へ正規化する
  #   （本文・タグ・ディレクトリ・スラッグは保持＝ユーザー編集を尊重）。
  # - KBMemo 独自記法（kbmemo-*）は公式 QR に無いため対象外。
  # - チェックリストノート「AsciiDoc 記法対応ノート」をロードマップ順・全 id で再構成する。
  class Seed
    Result = Data.define(:created, :updated, :notebook_added, :checklist, :paths, :errors) do
      def self.empty
        new(created: 0, updated: 0, notebook_added: 0, checklist: nil, paths: [], errors: [])
      end

      def summary_lines
        [
          "asciidoc_samples: created=#{created} updated=#{updated} notebook_added=#{notebook_added} checklist=#{checklist}",
          *paths.map { |line| "  #{line}" },
          *errors.map { |line| "  ERROR #{line}" }
        ]
      end
    end

    # 公式 QR に存在しない KBMemo 拡張は今回の対象外。
    EXCLUDED_IDS = %w[kbmemo-wiki kbmemo-diagram kbmemo-math].freeze

    SAMPLE_TAG       = "asciidoc"
    NOTEBOOK_SLUG    = "asciidoc_coverage"
    NOTEBOOK_TITLE   = "AsciiDoc カバレッジ"
    DIR_BUCKET       = "public"
    DIR_SEGMENT      = "asciidoc"
    MARKER_KEY       = "asciidoc_sample"
    CHECKLIST_TITLE  = "AsciiDoc 記法対応ノート"
    ROADMAP_SOURCE   = "architecture/asciidoc-syntax-coverage-roadmap.adoc"
    QR_URL           = "https://docs.asciidoctor.org/asciidoc/latest/syntax-quick-reference/"

    # id ちょうど・サフィックス付き以外で既存メモを拾うための別名。
    SPECIAL_ALIASES = {
      "paragraphs-literal" => [ "Literal paragraph (AsciiDoc 記法チェック)", "Literal paragraph" ]
    }.freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(account: nil, dry_run: false, fixture_path: nil)
      @account = resolve_account(account)
      @dry_run = dry_run
      @entries = Fixture.load(*[ fixture_path ].compact)
    end

    def call
      result = Result.empty
      directory = ensure_directory!
      notebook = ensure_notebook!
      sampled_ids = []

      target_entries.each do |entry|
        outcome = upsert_sample(entry, directory: directory, notebook: notebook)
        sampled_ids << entry.syntax_ref_id if outcome.delete(:sampled)
        result = merge(result, **outcome)
      rescue StandardError => e
        result = merge(result, error: "#{entry.syntax_ref_id}: #{e.class}: #{e.message}")
      end

      checklist_state = rebuild_checklist!(directory: directory, notebook: notebook, sampled_ids: sampled_ids.to_set)
      result.with(checklist: checklist_state)
    end

    private

    def target_entries
      @entries.reject { |entry| EXCLUDED_IDS.include?(entry.syntax_ref_id) }
    end

    def resolve_account(account)
      return account if account.is_a?(Account)
      return Account.find(account) if account.present?

      env_id = ENV["KBMEMO_DOCS_SYNC_ACCOUNT_ID"].presence
      return Account.find(env_id) if env_id.present?

      Account.find_by(admin: true) || Account.order(:id).first ||
        raise(ArgumentError, "対象アカウントがありません")
    end

    def ensure_directory!
      return MemoDirectory.find_by("full_path LIKE ?", "%/#{DIR_SEGMENT}") if @dry_run

      MemoDirectory::UserSpace.ensure_subdirectory!(@account, DIR_SEGMENT, bucket: DIR_BUCKET)
    end

    def ensure_notebook!
      notebook = Notebook.find_or_initialize_by(account: @account, slug: NOTEBOOK_SLUG)
      notebook.title = NOTEBOOK_TITLE if notebook.title.blank?
      notebook.publication_kind ||= :notes
      notebook.description = "AsciiDoc 記法カバレッジのサンプルメモ集" if notebook.description.blank?
      notebook.save! unless @dry_run
      notebook
    end

    def upsert_sample(entry, directory:, notebook:)
      id = entry.syntax_ref_id
      memo = find_existing(id)

      if @dry_run
        action = memo ? "would update" : "would create"
        return { paths: [ "#{id}: #{action}" ], sampled: true }
      end

      if memo
        normalize_existing!(memo, id)
        counters = { updated: 1, paths: [ "#{id}: normalized memo##{memo.id}" ] }
      else
        memo = create_sample!(entry, directory)
        counters = { created: 1, paths: [ "#{id}: created memo##{memo.id}" ] }
      end

      counters.merge(notebook: notebook, memo: memo, sampled: true)
        .then { |c| add_to_notebook(c) }
    end

    def add_to_notebook(counters)
      memo = counters.delete(:memo)
      notebook = counters.delete(:notebook)
      return counters if memo.nil? || notebook.nil?

      already = NotebookMemo.exists?(notebook: notebook, memo: memo)
      Notebooks::AddMemo.call(notebook: notebook, memo: memo) unless already
      counters[:notebook_added] = 1 unless already
      counters
    end

    def find_existing(id)
      by_marker = Memo.where(account_id: @account.id)
        .where("json_extract(properties, '$.#{MARKER_KEY}.syntax_ref_id') = ?", id)
        .first
      return by_marker if by_marker

      candidate_titles(id).each do |title|
        memo = Memo.find_by(account_id: @account.id, title: title)
        return memo if memo
      end
      nil
    end

    def candidate_titles(id)
      [ id, "#{id} (AsciiDoc 記法チェック)", *SPECIAL_ALIASES.fetch(id, []) ]
    end

    def normalize_existing!(memo, id)
      props = memo.properties.presence || {}
      props[MARKER_KEY] ||= {
        "syntax_ref_id" => id,
        "source" => "manual",
        "seeded_at" => Time.current.iso8601
      }
      memo.update!(title: id, title_manual: true, properties: props)
    end

    def create_sample!(entry, directory)
      memo = Memo.new(
        account: @account,
        memo_directory: directory,
        title: entry.syntax_ref_id,
        title_manual: true,
        slug: Memo.normalize_slug_fragment(entry.syntax_ref_id),
        slug_manual: true,
        body: sample_body(entry),
        visibility: :owner_read_write,
        properties: {
          MARKER_KEY => {
            "syntax_ref_id" => entry.syntax_ref_id,
            "source" => "syntax-quick-reference",
            "seeded_at" => Time.current.iso8601
          }
        }
      )
      memo.save!
      memo.assign_tags_from_list(SAMPLE_TAG)
      memo.save!
      memo
    end

    def sample_body(entry)
      "= #{entry.syntax_ref_id}\n\n#{entry.body}\n"
    end

    def rebuild_checklist!(directory:, notebook:, sampled_ids:)
      note = Memo.find_by(account_id: @account.id, title: CHECKLIST_TITLE)
      return "missing (dry run)" if note.nil? && @dry_run

      body = build_checklist_body(sampled_ids)
      return "would rebuild" if @dry_run

      if note
        note.update!(body: body)
        state = "updated memo##{note.id}"
      else
        note = Memo.new(
          account: @account,
          memo_directory: directory,
          title: CHECKLIST_TITLE,
          title_manual: true,
          slug: Memo.normalize_slug_fragment(CHECKLIST_TITLE),
          slug_manual: true,
          body: body,
          visibility: :owner_read_write
        )
        note.save!
        note.assign_tags_from_list(SAMPLE_TAG)
        note.save!
        state = "created memo##{note.id}"
      end

      unless NotebookMemo.exists?(notebook: notebook, memo: note)
        Notebooks::AddMemo.call(notebook: notebook, memo: note)
      end
      state
    end

    def build_checklist_body(sampled_ids)
      lines = []
      lines << "= #{CHECKLIST_TITLE}"
      lines << ""
      if (slug = roadmap_slug)
        lines << "ロードマップ: [[#{slug}]]"
        lines << ""
      end
      lines << "各 id は #{QR_URL}[Syntax Quick Reference] 由来。"
      lines << "チェック済み = サンプルメモあり。KBMemo 拡張（kbmemo-*）は公式 QR 外のため別途。"
      lines << ""

      ordered_categories.each do |category|
        lines << "== #{category}"
        lines << "[%interactive]"
        @entries.select { |e| e.category == category }.each do |entry|
          id = entry.syntax_ref_id
          if sampled_ids.include?(id)
            lines << "* [x] [[#{id}]]"
          else
            lines << "* [ ] #{id}（KBMemo 拡張・別途）"
          end
        end
        lines << ""
      end

      "#{lines.join("\n").rstrip}\n"
    end

    def ordered_categories
      @entries.map(&:category).uniq
    end

    def roadmap_slug
      Memo.where(account_id: @account.id)
        .where("json_extract(properties, '$.docs_sync.source_path') = ?", ROADMAP_SOURCE)
        .pick(:slug)
    end

    def merge(result, created: 0, updated: 0, notebook_added: 0, paths: [], error: nil)
      result.with(
        created: result.created + created,
        updated: result.updated + updated,
        notebook_added: result.notebook_added + notebook_added,
        paths: result.paths + Array(paths),
        errors: error ? result.errors + [ error ] : result.errors
      )
    end
  end
end
