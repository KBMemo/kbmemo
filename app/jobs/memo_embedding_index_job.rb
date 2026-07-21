# frozen_string_literal: true

class MemoEmbeddingIndexJob < ApplicationJob
  queue_as :kbmemo_site

  def perform(memo_id)
    memo = Memo.find_by(id: memo_id)
    return unless memo

    Chat::Tools::MemoEmbeddingIndexer.new.index_memo(memo)
  end
end
