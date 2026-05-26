# frozen_string_literal: true

module Notebooks
  class Error < StandardError; end

  class Publish
    def self.call(notebook:)
      new(notebook: notebook).call
    end

    def initialize(notebook:)
      @notebook = notebook
    end

    def call
      raise Error, "自分用ノートは公開できません" if @notebook.notes?

      @notebook.update!(published_at: Time.current)
      @notebook
    end
  end
end
