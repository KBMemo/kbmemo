# frozen_string_literal: true

module Notebooks
  class RemoveMemo
    def self.call(notebook:, memo:)
      new(notebook: notebook, memo: memo).call
    end

    def initialize(notebook:, memo:)
      @notebook = notebook
      @memo = memo
    end

    def call
      entry = @notebook.notebook_memos.find_by!(memo_id: @memo.id)
      entry.destroy!
    end
  end
end
