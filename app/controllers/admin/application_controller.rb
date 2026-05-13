# frozen_string_literal: true

# Administrate の基底。アプリのログイン（Rodauth）に加え、admin フラグで制限する。
module Admin
  class ApplicationController < Administrate::ApplicationController
    helper AdministrateAssetHelper

    before_action :require_authentication_and_admin

    private

    def require_authentication_and_admin
      rodauth.require_account
      return if rodauth.rails_account&.admin?

      redirect_to root_path, alert: "管理画面にアクセスする権限がありません。"
    end
  end
end
