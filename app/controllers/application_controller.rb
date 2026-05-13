class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include Pundit::Authorization

  before_action :require_authentication

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def require_authentication
    rodauth.require_account
  end

  def pundit_user
    rodauth.rails_account
  end

  def user_not_authorized
    flash[:alert] = "権限がありません。"
    redirect_back(fallback_location: root_path, allow_other_host: false)
  end
end
