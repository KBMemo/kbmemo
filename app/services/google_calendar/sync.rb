# frozen_string_literal: true

module GoogleCalendar
  # Google Calendar イベントをアカウント配下の calendar/ ディレクトリへ upsert する。
  class Sync
    Result = Data.define(:created, :updated, :deleted, :skipped, :paths, :errors) do
      def self.empty
        new(created: 0, updated: 0, deleted: 0, skipped: 0, paths: [], errors: [])
      end

      def summary_lines
        [
          "created=#{created} updated=#{updated} deleted=#{deleted} skipped=#{skipped}",
          *paths.map { |line| "  #{line}" },
          *errors.map { |line| "  ERROR #{line}" }
        ]
      end
    end

    LOOKBACK_DAYS = 7
    LOOKAHEAD_DAYS = 90
    TAG = EventMapper::TAG

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(account:, dry_run: false, client: nil)
      @account = account
      @dry_run = dry_run
      @client = client
    end

    def call
      return Result.new(**empty_counters, paths: [ "Google Calendar 未連携" ], errors: []) unless @account.google_calendar_connected?
      return Result.new(**empty_counters, paths: [ "Google Calendar OAuth 未設定または不正" ], errors: []) unless Credentials.valid?

      @sync_token_reset = false
      result = Result.empty
      calendar_id = calendar_id_for_account
      sync_token = @account.google_calendar_sync_token
      page_token = nil
      next_sync_token = nil

      loop do
        response = client.list_events(
          calendar_id: calendar_id,
          sync_token: sync_token,
          time_min: sync_token.present? ? nil : time_min,
          time_max: sync_token.present? ? nil : time_max,
          page_token: page_token
        )

        response.items.each do |event|
          result = merge_result(result, sync_event(event, calendar_id: calendar_id))
        end

        next_sync_token = response.next_sync_token if response.next_sync_token.present?
        page_token = response.next_page_token
        break if page_token.blank?
      end

      touch_sync_meta!(next_sync_token) unless @dry_run
      result
    rescue Client::SyncTokenExpired
      raise if @sync_token_reset

      @account.clear_google_calendar_sync_token! unless @dry_run
      @sync_token_reset = true
      call
    rescue Client::Error, Google::Auth::AuthorizationError => e
      Result.new(**empty_counters, paths: [], errors: [ e.message ])
    end

    private

    def empty_counters
      { created: 0, updated: 0, deleted: 0, skipped: 0 }
    end

    def client
      @client ||= Client.new(account: @account)
    end

    def calendar_id_for_account
      @account.google_calendar_meta.fetch("calendar_id", "primary")
    end

    def time_min
      LOOKBACK_DAYS.days.ago.beginning_of_day
    end

    def time_max
      LOOKAHEAD_DAYS.days.from_now.end_of_day
    end

    def sync_event(event, calendar_id:)
      memo = find_memo(calendar_id: calendar_id, event_id: event.id)

      if event.status == "cancelled"
        return delete_memo(memo, event.id) if memo

        return outcome_line(event.id, "skipped cancelled (no memo)", counters: { skipped: 1 })
      end

      if memo && memo_unchanged?(memo, event, calendar_id)
        return outcome_line(event.id, "skipped unchanged memo##{memo.id}", counters: { skipped: 1 })
      end

      if @dry_run
        action = memo ? "would update memo##{memo.id}" : "would create"
        return outcome_line(event.id, "#{action} title=#{event.summary.inspect}", counters: { skipped: 1 })
      end

      if memo
        update_memo!(memo, event, calendar_id)
        outcome_line(event.id, "updated memo##{memo.id}", counters: { updated: 1 })
      else
        memo = create_memo!(event, calendar_id)
        outcome_line(event.id, "created memo##{memo.id}", counters: { created: 1 })
      end
    end

    def find_memo(calendar_id:, event_id:)
      path_event = MemoPropertiesSql.json_text_at("google_calendar", "event_id")
      path_calendar = MemoPropertiesSql.json_text_at("google_calendar", "calendar_id")
      Memo.where(account_id: @account.id)
        .where("#{path_event} = ? AND #{path_calendar} = ?", event_id, calendar_id)
        .first
    end

    def memo_unchanged?(memo, event, calendar_id)
      payload = EventMapper.properties_payload(event, calendar_id)
      memo.properties.dig("google_calendar", "etag") == payload["etag"]
    end

    def create_memo!(event, calendar_id)
      memo = Memo.new(
        account: @account,
        memo_directory: calendar_directory!,
        title: "placeholder",
        body: ""
      )
      EventMapper.apply!(memo: memo, event: event, calendar_id: calendar_id)
      memo.save!
      assign_tags!(memo)
      memo
    end

    def update_memo!(memo, event, calendar_id)
      EventMapper.apply!(memo: memo, event: event, calendar_id: calendar_id)
      memo.save!
      assign_tags!(memo)
      memo
    end

    def delete_memo(memo, event_id)
      if @dry_run
        return outcome_line(event_id, "would delete memo##{memo.id}", counters: { skipped: 1 })
      end

      memo.destroy!
      outcome_line(event_id, "deleted memo##{memo.id}", counters: { deleted: 1 })
    end

    def assign_tags!(memo)
      labels = (memo.tags.map(&:name) + [ TAG ]).uniq
      memo.assign_tags_from_list(labels.join(", "))
      memo.save!
    end

    def calendar_directory!
      MemoDirectory::UserSpace.ensure_subdirectory!(@account, "calendar")
    end

    def touch_sync_meta!(next_sync_token)
      meta = @account.google_calendar_meta.stringify_keys.dup
      meta["sync_token"] = next_sync_token if next_sync_token.present?
      meta["last_synced_at"] = Time.current.iso8601
      @account.update!(google_calendar_meta: meta)
    end

    def merge_result(result, outcome)
      Result.new(
        created: result.created + outcome.created,
        updated: result.updated + outcome.updated,
        deleted: result.deleted + outcome.deleted,
        skipped: result.skipped + outcome.skipped,
        paths: result.paths + outcome.paths,
        errors: result.errors + outcome.errors
      )
    end

    def outcome_line(event_id, message, counters:)
      Result.new(
        created: counters[:created] || 0,
        updated: counters[:updated] || 0,
        deleted: counters[:deleted] || 0,
        skipped: counters[:skipped] || 0,
        paths: [ "#{event_id}: #{message}" ],
        errors: counters[:errors].to_a
      )
    end
  end
end
