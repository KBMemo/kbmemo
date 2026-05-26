# frozen_string_literal: true

namespace :memo_wiki_links do
  desc "Rebuild memo_wiki_links for all memos"
  task rebuild: :environment do
    count = Memo.count
    puts "Rebuilding wiki link index for #{count} memos..."
    MemoWikiLinkIndex.rebuild_all
    puts "Done. #{MemoWikiLink.count} edges indexed."
  end
end
