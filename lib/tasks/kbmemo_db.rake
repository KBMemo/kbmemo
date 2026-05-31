# frozen_string_literal: true

namespace :kbmemo do
  namespace :db do
    desc "Import primary DB data from SQLite into PostgreSQL (SOURCE=path CLEAR=1|0)"
    task import_sqlite: :environment do
      require Rails.root.join("lib/kbmemo/db/sqlite_importer")

      source = ENV.fetch("SOURCE") { Rails.root.join("storage/development.sqlite3") }
      clear = !%w[0 false no].include?(ENV.fetch("CLEAR", "1").to_s.downcase)

      Kbmemo::Db::SqliteImporter.call(path: source, clear: clear)
    end
  end
end
