# frozen_string_literal: true

module Notebooks
  # Notebook 目次ツリーを AsciiDoc ファイル群として書き出す。
  class Export
    Result = Data.define(:notebook, :written, :paths, :errors) do
      def summary_lines
        [
          "notebook=#{notebook.id} (#{notebook.title}) written=#{written}",
          *paths.map { |line| "  #{line}" },
          *errors.map { |line| "  ERROR #{line}" }
        ]
      end
    end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(notebook:, target_root:, dry_run: false)
      @notebook = notebook
      @target_root = Pathname.new(target_root)
      @dry_run = dry_run
    end

    def call
      entries = @notebook.notebook_memos.includes(:memo).order(:position, :id).to_a
      by_parent = entries.group_by(&:parent_id)
      counters = { written: 0, paths: [], errors: [] }

      (by_parent[nil] || []).each do |entry|
        write_entry!(entry, @target_root, by_parent, counters)
      end

      Result.new(notebook: @notebook, written: counters[:written], paths: counters[:paths], errors: counters[:errors])
    end

    private

    def write_entry!(entry, directory, by_parent, counters)
      memo = entry.memo
      filename = export_filename(memo)
      path = directory.join(filename)

      if @dry_run
        counters[:written] += 1
        counters[:paths] << "#{path}: would write"
      else
        path.parent.mkpath
        path.write(export_contents(memo), encoding: "UTF-8")
        counters[:written] += 1
        counters[:paths] << path.to_s
      end

      children = by_parent[entry.id] || []
      child_dir = directory.join(Memo.slug_stem(memo.slug, memo_id: memo.id) || "memo-#{memo.id}")
      children.each do |child|
        write_entry!(child, child_dir, by_parent, counters)
      end
    rescue StandardError => e
      counters[:errors] << "#{entry.memo.slug}: #{e.message}"
    end

    def export_filename(memo)
      stem = Memo.slug_stem(memo.slug, memo_id: memo.id).presence || "memo-#{memo.id}"
      "#{stem}.adoc"
    end

    def export_contents(memo)
      meta = {
        "title" => memo.title.to_s,
        "tags" => memo.tags.map(&:name).sort,
        "properties" => memo.properties.is_a?(Hash) ? memo.properties.stringify_keys : memo.properties,
        "exported_from" => {
          "memo_id" => memo.id,
          "notebook_id" => @notebook.id,
          "exported_at" => Time.current.iso8601
        }
      }
      yaml = meta.to_yaml.sub(/\A---\s*\n?/, "")
      body = memo.body.to_s
      body = "= #{memo.title}\n\n#{body}" unless body.match?(/\A=\s+/m)
      "---\n#{yaml.rstrip}\n---\n\n#{body}"
    end
  end
end
