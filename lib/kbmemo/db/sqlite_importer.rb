# frozen_string_literal: true

require "json"

module Kbmemo
  module Db
    # storage/*.sqlite3（旧 primary DB）から現在の PostgreSQL primary へデータをコピーする。
    class SqliteImporter
      INTERNAL_SQLITE_TABLES = %w[sqlite_sequence ar_internal_metadata schema_migrations].freeze

      # FK 依存の浅い順（import 時は参照整合性チェックを一時無効化）
      TABLE_ORDER = %w[
        accounts
        memo_groups
        memo_directories
        tags
        boards
        board_columns
        memos
        memo_tags
        memo_wiki_links
        memo_group_memberships
        memo_view_histories
        notebooks
        notebook_memos
        account_login_change_keys
        account_password_reset_keys
        account_remember_keys
        account_verification_keys
      ].freeze

      Model = Struct.new(:table, :klass, keyword_init: true)

      def self.call(path:, clear: true)
        new(path: path, clear: clear).call
      end

      def initialize(path:, clear:)
        @path = Pathname.new(path)
        @clear = clear
        @sqlite = sqlite3_database
        @sqlite.results_as_hash = false
        @counts = {}
      end

      def call
        raise ArgumentError, "SQLite file not found: #{@path}" unless @path.file?

        unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
          raise "kbmemo:db:import_sqlite requires PostgreSQL as the target adapter"
        end

        puts "Importing from #{@path} → #{ActiveRecord::Base.connection_db_config.database}"

        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.disable_referential_integrity do
            clear_target! if @clear
            import_tables!
            reset_sequences!
          end
        end

        print_summary
        @counts
      end

      private

      def clear_target!
        TABLE_ORDER.reverse_each do |table|
          next unless target_table?(table)

          ActiveRecord::Base.connection.execute("DELETE FROM #{quote_table(table)}")
        end
      end

      def import_tables!
        TABLE_ORDER.each do |table|
          import_table!(table)
        end
      end

      def order_clause(table)
        case table
        when "memo_directories"
          "ORDER BY LENGTH(full_path), full_path"
        when "notebook_memos"
          "ORDER BY COALESCE(parent_id, 0), id"
        else
          ""
        end
      end

      def import_table!(table)
        return unless target_table?(table)
        return unless sqlite_table?(table)

        columns = shared_columns(table)
        if columns.empty?
          puts "  skip #{table} (no shared columns)"
          return
        end

        rows = @sqlite.execute("SELECT #{columns.map { |c| quote_column(c) }.join(', ')} FROM #{quote_table(table)} #{order_clause(table)}")
        if rows.empty?
          @counts[table] = 0
          puts "  #{table}: 0"
          return
        end

        records = rows.map { |row| row_to_record(columns, row, table) }
        quoted_table = quote_table(table)
        column_list = columns.map { |c| quote_column(c) }.join(", ")

        records.each_slice(500) do |batch|
          values_sql = batch.map { |record|
            "(" + columns.map { |col| quote_value(record[col], table, col) }.join(", ") + ")"
          }.join(", ")
          sql = "INSERT INTO #{quoted_table} (#{column_list}) VALUES #{values_sql}"
          ActiveRecord::Base.connection.execute(sql)
        end

        @counts[table] = records.size
        puts "  #{table}: #{records.size}"
      end

      def row_to_record(columns, row, table)
        columns.zip(row).to_h.tap do |record|
          normalize_record!(record, table)
        end
      end

      def normalize_record!(record, table)
        record.each do |key, value|
          next if value.nil?

          case json_column?(table, key)
          when true
            record[key] = value.is_a?(String) ? JSON.parse(value) : value
          end
        end
      end

      def json_column?(table, column)
        @json_columns ||= {}
        @json_columns[table] ||= ActiveRecord::Base.connection.columns(table).select { |c| json_column_type?(c) }.map(&:name)
        @json_columns[table].include?(column)
      end

      def json_column_type?(column)
        column.type.in?(%i[json jsonb]) || column.sql_type.to_s.match?(/\Ajson/i)
      end

      def json_cast(table, column)
        sql_type = ActiveRecord::Base.connection.columns(table).find { |c| c.name == column }&.sql_type.to_s.downcase
        sql_type.include?("jsonb") ? "::jsonb" : "::json"
      end

      def shared_columns(table)
        sqlite_cols = sqlite_columns(table)
        pg_cols = ActiveRecord::Base.connection.columns(table).map(&:name)
        sqlite_cols & pg_cols
      end

      def sqlite_columns(table)
        @sqlite.execute("PRAGMA table_info(#{quote_table(table)})").map { |row| row[1] }
      end

      def sqlite_table?(table)
        @sqlite.get_first_value(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table]
        )
      end

      def target_table?(table)
        TABLE_ORDER.include?(table) && ActiveRecord::Base.connection.table_exists?(table)
      end

      def reset_sequences!
        TABLE_ORDER.each do |table|
          next unless target_table?(table)
          next unless ActiveRecord::Base.connection.columns(table).any?(&:serial?)

          ActiveRecord::Base.connection.reset_pk_sequence!(table)
        end
      end

      def print_summary
        total = @counts.values.sum
        puts "Done. #{total} rows imported across #{@counts.size} tables."
      end

      def quote_table(name)
        ActiveRecord::Base.connection.quote_table_name(name)
      end

      def quote_column(name)
        ActiveRecord::Base.connection.quote_column_name(name)
      end

      def quote_value(value, table, column)
        case value
        when Hash, Array
          ActiveRecord::Base.connection.quote(value.to_json) + json_cast(table, column)
        else
          if boolean_column?(table, column)
            ActiveRecord::Base.connection.quote(value == true || value == 1)
          else
            ActiveRecord::Base.connection.quote(value)
          end
        end
      end

      def boolean_column?(table, column)
        @boolean_columns ||= {}
        @boolean_columns[table] ||= ActiveRecord::Base.connection.columns(table).select { |c| c.type == :boolean }.map(&:name)
        @boolean_columns[table].include?(column)
      end

      def sqlite3_database
        require "sqlite3"
        SQLite3::Database.new(@path.to_s)
      rescue LoadError
        raise LoadError,
          "sqlite3 gem is required for kbmemo:db:import_sqlite — run `bundle install` on this host"
      end
    end
  end
end
