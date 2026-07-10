# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_account

    def connect
      self.current_account = find_verified_account
      reject_unauthorized_connection unless current_account
    end

    private

    def find_verified_account
      rodauth = RodauthApp.rodauth(request.env)
      return nil unless rodauth.logged_in?

      rodauth.rails_account
    end
  end
end
