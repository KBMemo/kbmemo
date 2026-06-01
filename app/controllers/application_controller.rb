class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include Pundit::Authorization

  before_action :require_authentication
  before_action :set_nav_boards
  before_action :set_nav_notebooks

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def require_authentication
    rodauth.require_account
  end

  def pundit_user
    rodauth.rails_account
  end

  def user_not_authorized
    if json_request?
      render json: { error: "権限がありません。" }, status: :forbidden
      return
    end

    flash[:alert] = "権限がありません。"
    redirect_back(fallback_location: root_path, allow_other_host: false)
  end

  def json_request?
    request.format.json? || request.headers["Accept"].to_s.include?("application/json")
  end

  def set_nav_boards
    @nav_boards = policy_scope(Board).order(updated_at: :desc)
  end

  def set_nav_notebooks
    @nav_notebooks = policy_scope(Notebook).order_by_latest_memo_updated_at
  end
end
