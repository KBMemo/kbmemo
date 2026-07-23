# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    @overview = DashboardOverview.new(
      account: rodauth.rails_account,
      memo_scope: policy_scope(Memo),
      board_scope: policy_scope(Board),
      notebook_scope: policy_scope(Notebook)
    )
  end
end
