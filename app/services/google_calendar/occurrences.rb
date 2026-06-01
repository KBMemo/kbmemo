# frozen_string_literal: true

require "ice_cube"

module GoogleCalendar
  # 同期済みメモの google_calendar.recurrence（RRULE）を日付列に展開する。
  class Occurrences
    class << self
      def recurring?(memo)
        recurrence_rules(memo).any?
      end

      def occurs_on?(memo, date)
        date = date.to_date
        dates_in_range(memo, date..date).include?(date)
      end

      def dates_in_range(memo, range)
        range = normalize_range(range)
        return dates_for_single(memo, range) unless recurring?(memo)

        build_schedule(memo)&.occurrences_between(range.begin.beginning_of_day, range.end.end_of_day)
          &.map { |time| time.in_time_zone.to_date }
          &.uniq
          &.select { |day| range.cover?(day) }
          &.reject { |day| cancelled_occurrences(memo).include?(day) } || []
      rescue ArgumentError, IceCube::Error
        dates_for_single(memo, range)
      end

      private

      def dates_for_single(memo, range)
        day = memo.scheduled_on
        day && range.cover?(day) ? [ day ] : []
      end

      def normalize_range(range)
        range.begin.to_date..range.end.to_date
      end

      def recurrence_rules(memo)
        Array(memo.properties.dig("google_calendar", "recurrence")).grep(/\ARRULE:/)
      end

      def cancelled_occurrences(memo)
        Array(memo.properties.dig("google_calendar", "cancelled_occurrences")).filter_map do |raw|
          Date.iso8601(raw.to_s)
        rescue ArgumentError
          nil
        end
      end

      def build_schedule(memo)
        gcal = memo.properties.fetch("google_calendar", {})
        start_time = parse_start_time(gcal)
        return nil unless start_time

        schedule = IceCube::Schedule.new(start_time)
        Array(gcal["recurrence"]).each do |line|
          case line
          when /\ARRULE:(.*)\z/
            schedule.add_recurrence_rule(IceCube::Rule.from_ical(Regexp.last_match(1)))
          when /\AEXDATE;VALUE=DATE:(.*)\z/
            parse_exdate_dates(Regexp.last_match(1)).each { |day| schedule.add_exception_time(day.beginning_of_day) }
          when /\AEXDATE;TZID=[^:]+:(.*)\z/
            parse_exdate_timestamps(Regexp.last_match(1)).each { |time| schedule.add_exception_time(time) }
          end
        end
        schedule
      end

      def parse_start_time(gcal)
        raw = gcal["starts_at"].presence
        return nil if raw.blank?

        if gcal["all_day"]
          Date.iso8601(raw.to_s).in_time_zone.beginning_of_day
        else
          Time.zone.parse(raw.to_s)
        end
      rescue ArgumentError, TypeError
        nil
      end

      def parse_exdate_dates(raw)
        raw.to_s.split(",").filter_map do |token|
          Date.strptime(token.strip, "%Y%m%d")
        rescue ArgumentError
          nil
        end
      end

      def parse_exdate_timestamps(raw)
        raw.to_s.split(",").filter_map do |token|
          Time.zone.parse(token.strip.sub(/\A;TZID=[^:]+:/, ""))
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
