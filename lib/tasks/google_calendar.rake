# frozen_string_literal: true

namespace :kbmemo do
  namespace :google_calendar do
    desc <<~DESC.squish
      Import Google Calendar events into memos for connected accounts.
      Env: ACCOUNT_ID (optional), DRY_RUN=1
    DESC
    task sync: :environment do
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
      accounts = if (id = ENV["ACCOUNT_ID"].presence)
        Account.where(id: id)
      else
        Account.where.not(google_calendar_refresh_token: nil)
      end

      abort "no connected accounts" if accounts.none?

      accounts.find_each do |account|
        result = GoogleCalendar::Sync.call(account: account, dry_run: dry_run)
        puts "account=#{account.id} kbmemo:google_calendar:sync#{dry_run ? ' (dry run)' : ''}"
        result.summary_lines.each { |line| puts line }
      end
    end
  end
end
