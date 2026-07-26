# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    schedule_month = parse_schedule_month(params[:schedule_month])
    @overview = DashboardOverview.new(
      account: rodauth.rails_account,
      memo_scope: policy_scope(Memo),
      board_scope: policy_scope(Board),
      notebook_scope: policy_scope(Notebook)
    )
    @schedule_calendar = BoardScheduleCalendar.new(
      board: nil,
      memos_scope: policy_scope(Memo).where(account_id: rodauth.rails_account.id),
      month: schedule_month
    )
    @memo_templates = policy_scope(MemoTemplate).order(:name)
  end

  private

  def parse_schedule_month(raw)
    return Date.current.beginning_of_month if raw.blank?

    Date.strptime(raw.to_s, "%Y-%m")
  rescue ArgumentError
    Date.current.beginning_of_month
  end
end
