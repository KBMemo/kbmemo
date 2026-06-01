# frozen_string_literal: true

module GoogleCalendar
  # アカウント配下の Google Calendar 同期メモを削除し、sync_token をリセットする。
  class Clear
    Result = Data.define(:deleted_count, :errors) do
      def success?
        errors.empty?
      end
    end

    def self.call(account:)
      new(account: account).call
    end

    def initialize(account:)
      @account = account
    end

    def call
      deleted_count = 0
      synced_memos.find_each do |memo|
        memo.destroy!
        deleted_count += 1
      end
      @account.clear_google_calendar_sync_token!
      Result.new(deleted_count: deleted_count, errors: [])
    rescue StandardError => e
      Result.new(deleted_count: deleted_count, errors: [ e.message ])
    end

    def synced_memos
      event_id_sql = MemoPropertiesSql.json_text_at("google_calendar", "event_id")
      Memo.where(account_id: @account.id)
        .where("#{event_id_sql} IS NOT NULL AND #{event_id_sql} != ''")
    end

    private

    attr_reader :account
  end
end
