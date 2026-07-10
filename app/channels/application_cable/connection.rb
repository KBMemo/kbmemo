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
      rodauth = request.env["rodauth"] || rodauth_from_session
      return nil unless rodauth&.logged_in?

      rodauth.rails_account
    end

    def rodauth_from_session
      session_data = request.session.to_h
      return nil if session_data.blank?

      Rodauth::Rails.rodauth(session: session_data)
    rescue Rodauth::InternalRequestError, Rodauth::Rails::Error
      nil
    end
  end
end
