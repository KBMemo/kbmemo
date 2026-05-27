# frozen_string_literal: true

module KbmemoDocs
  SYNC_TARGETS = %w[system share].freeze
  SYNC_TARGET = (ENV["KBMEMO_DOCS_SYNC_TARGET"].presence || "system").freeze
  SYNC_BUCKET = "share"
  DEV_DOCS_SEGMENT = "dev-docs"
  SYSTEM_DOCS_SEGMENT = "docs"
  NOTEBOOK_SLUG = "dev-docs"
  NOTEBOOK_TITLE = "Developer Docs"
end
