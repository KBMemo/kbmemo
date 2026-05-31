# frozen_string_literal: true

# PostgreSQL 上の memos.properties（jsonb）向け SQL 断片。
# 方針: docs/architecture/memo-properties.adoc
module MemoPropertiesSql
  module_function

  # properties -> 'a' -> 'b' ->> 'c'
  def json_text_at(*keys)
    raise ArgumentError, "at least one key required" if keys.empty?

    sql = "properties"
    keys[0..-2].each { |key| sql += " -> #{quote_json_key(key)}" }
    sql += " ->> #{quote_json_key(keys.last)}"
    sql
  end

  def quote_json_key(key)
    ActiveRecord::Base.connection.quote(key.to_s)
  end
end
