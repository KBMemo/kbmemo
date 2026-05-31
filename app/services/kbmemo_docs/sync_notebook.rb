# frozen_string_literal: true

module KbmemoDocs
  # docs_sync メモを Developer Docs ノートブックへツリー登録する。
  class SyncNotebook
    Result = Data.define(:notebook, :added, :updated, :skipped, :paths, :errors) do
      def self.empty
        new(notebook: nil, added: 0, updated: 0, skipped: 0, paths: [], errors: [])
      end

      def summary_lines
        header = notebook ? "notebook=#{notebook.id} (#{notebook.title})" : "notebook=none"
        [
          "#{header} added=#{added} updated=#{updated} skipped=#{skipped}",
          *paths.map { |line| "  #{line}" },
          *errors.map { |line| "  ERROR #{line}" }
        ]
      end
    end

    Plan = Data.define(:memo, :source_path, :parent_memo_id, :position)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(account: nil, notebook_slug: nil, notebook_title: nil, dry_run: false)
      @account = resolve_account(account)
      @notebook_slug = notebook_slug.presence || ENV["KBMEMO_DOCS_SYNC_NOTEBOOK_SLUG"].presence || NOTEBOOK_SLUG
      @notebook_title = notebook_title.presence || ENV["KBMEMO_DOCS_SYNC_NOTEBOOK_TITLE"].presence || NOTEBOOK_TITLE
      @dry_run = dry_run
    end

    def call
      memos = docs_sync_memos
      return Result.new(notebook: nil, added: 0, updated: 0, skipped: 0, paths: [ "no docs_sync memos" ], errors: []) if memos.empty?

      notebook = find_or_create_notebook!
      plans = build_plans(memos)
      return summarize(notebook, apply_dry_run(notebook, plans)) if @dry_run

      summarize(notebook, apply!(notebook, plans))
    end

    private

    def resolve_account(account)
      if account.is_a?(Account)
        account
      elsif account.present?
        Account.find(account)
      else
        env_id = ENV["KBMEMO_DOCS_SYNC_ACCOUNT_ID"].presence
        return Account.find(env_id) if env_id.present?

        Account.find_by(admin: true) || Account.order(:id).first ||
          raise(ArgumentError, "同期先アカウントがありません")
      end
    end

    def docs_sync_memos
      path_sql = MemoPropertiesSql.json_text_at("docs_sync", "source_path")
      Memo.where(account_id: @account.id)
        .where("#{path_sql} IS NOT NULL")
        .order(Arel.sql(path_sql))
        .to_a
    end

    def find_or_create_notebook!
      notebook = Notebook.find_or_initialize_by(account: @account, slug: @notebook_slug)
      notebook.title = @notebook_title if notebook.title.blank?
      notebook.publication_kind ||= :notes
      notebook.description = "Git docs/ から同期された開発ドキュメント" if notebook.description.blank?
      notebook.save!
      notebook
    end

    def build_plans(memos)
      sorted = memos.sort_by do |memo|
        source_path = memo.properties.dig("docs_sync", "source_path")
        [ source_path.count("/"), source_path ]
      end
      dir_anchor = {}
      rows = sorted.map do |memo|
        source_path = memo.properties.dig("docs_sync", "source_path")
        dir = File.dirname(source_path)
        parent_memo_id = nil

        if dir != "."
          parts = dir.split("/")
          if parts.size >= 2
            parent_dir = parts.first(parts.size - 1).join("/")
            parent_memo_id = dir_anchor[parent_dir]
          end
          dir_anchor[dir] ||= memo.id
        end

        { memo: memo, source_path: source_path, parent_memo_id: parent_memo_id }
      end

      rows.group_by { |row| row[:parent_memo_id] }.flat_map do |parent_memo_id, group|
        group.each_with_index.map do |row, position|
          Plan.new(
            memo: row[:memo],
            source_path: row[:source_path],
            parent_memo_id: parent_memo_id,
            position: position
          )
        end
      end.sort_by { |plan| [ plan.source_path.count("/"), plan.source_path ] }
    end

    def apply_dry_run(notebook, plans)
      counters = { added: 0, updated: 0, skipped: 0, paths: [], errors: [] }
      entry_by_memo_id = notebook.notebook_memos.index_by(&:memo_id)

      plans.each do |plan|
        entry = entry_by_memo_id[plan.memo.id]
        parent_entry_id = resolve_parent_entry_id(notebook, plan.parent_memo_id, entry_by_memo_id)

        if entry
          if entry.parent_id == parent_entry_id && entry.position == plan.position
            counters[:skipped] += 1
            counters[:paths] << "#{plan.source_path}: unchanged"
          else
            counters[:updated] += 1
            counters[:paths] << "#{plan.source_path}: would update parent=#{parent_entry_id.inspect} position=#{plan.position}"
          end
        else
          counters[:added] += 1
          counters[:paths] << "#{plan.source_path}: would add"
        end
      end
      counters
    end

    def apply!(notebook, plans)
      counters = { added: 0, updated: 0, skipped: 0, paths: [], errors: [] }
      entry_by_memo_id = notebook.notebook_memos.index_by(&:memo_id)

      plans.each do |plan|
        entry = entry_by_memo_id[plan.memo.id]
        parent_entry_id = resolve_parent_entry_id(notebook, plan.parent_memo_id, entry_by_memo_id)

        if entry.nil?
          Notebooks::AddMemo.call(notebook: notebook, memo: plan.memo)
          entry = NotebookMemo.find_by!(notebook: notebook, memo: plan.memo)
          entry_by_memo_id[plan.memo.id] = entry
          counters[:added] += 1
          action = "added"
        elsif entry.parent_id == parent_entry_id && entry.position == plan.position
          counters[:skipped] += 1
          counters[:paths] << "#{plan.source_path}: unchanged"
          next
        else
          counters[:updated] += 1
          action = "updated"
        end

        Notebooks::MoveMemo.call(
          notebook: notebook,
          entry: entry,
          parent_id: parent_entry_id,
          position: plan.position
        )
        entry_by_memo_id[plan.memo.id] = entry.reload
        counters[:paths] << "#{plan.source_path}: #{action} parent=#{parent_entry_id.inspect} position=#{plan.position}" unless action.nil?
      rescue Notebooks::Error => e
        counters[:errors] << "#{plan.source_path}: #{e.message}"
      end

      counters
    end

    def resolve_parent_entry_id(notebook, parent_memo_id, entry_by_memo_id)
      return nil if parent_memo_id.blank?

      entry_by_memo_id[parent_memo_id]&.id ||
        NotebookMemo.find_by(notebook: notebook, memo_id: parent_memo_id)&.id
    end

    def summarize(notebook, counters)
      Result.new(
        notebook: notebook,
        added: counters[:added],
        updated: counters[:updated],
        skipped: counters[:skipped],
        paths: counters[:paths],
        errors: counters[:errors] || []
      )
    end
  end
end
