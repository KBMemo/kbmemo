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
      existing = @memo.notebook_memo
      if existing.present? && existing.notebook_id != @notebook.id
        if @memo.docs_sync_read_only?
          existing.destroy!
        else
          raise Error, "このメモは既に別のノートブックに含まれています"
        end
      end

      position = @notebook.notebook_memos.where(parent_id: nil).maximum(:position).to_i + 1
      NotebookMemo.find_or_initialize_by(notebook: @notebook, memo: @memo).tap do |entry|
        entry.position = position if entry.new_record?
        entry.save!
      end
    end
  end
end
