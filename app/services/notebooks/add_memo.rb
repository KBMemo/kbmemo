# frozen_string_literal: true

module Notebooks
  class AddMemo
    def self.call(notebook:, memo:)
      new(notebook: notebook, memo: memo).call
    end

    def initialize(notebook:, memo:)
      @notebook = notebook
      @memo = memo
    end

    def call
      if @memo.notebook_memo.present? && @memo.notebook_memo.notebook_id != @notebook.id
        raise Error, "このメモは既に別のノートブックに含まれています"
      end

      position = @notebook.notebook_memos.maximum(:position).to_i + 1
      NotebookMemo.find_or_initialize_by(notebook: @notebook, memo: @memo).tap do |entry|
        entry.position = position if entry.new_record?
        entry.save!
      end
    end
  end
end
