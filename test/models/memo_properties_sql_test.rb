# frozen_string_literal: true

require "test_helper"

class MemoPropertiesSqlTest < ActiveSupport::TestCase
  test "json_text_at builds nested PostgreSQL json path" do
    sql = MemoPropertiesSql.json_text_at("docs_sync", "source_path")
    assert_equal "properties -> 'docs_sync' ->> 'source_path'", sql
  end

  test "json_text_at builds top-level key path" do
    sql = MemoPropertiesSql.json_text_at("scheduled_on")
    assert_equal "properties ->> 'scheduled_on'", sql
  end
end
