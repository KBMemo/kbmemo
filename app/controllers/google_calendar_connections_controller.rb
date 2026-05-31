# frozen_string_literal: true

class GoogleCalendarConnectionsController < ApplicationController
  def connect
    unless GoogleCalendar::Credentials.valid?
      reason = GoogleCalendar::Credentials.misconfiguration_reason || "OAuth 設定が不正です"
      redirect_to edit_profile_path, alert: "Google Calendar OAuth: #{reason}"
      return
    end

    session[:google_calendar_oauth_state] = SecureRandom.urlsafe_base64(32)
    redirect_to GoogleCalendar::OAuth.authorization_url(
      state: session[:google_calendar_oauth_state],
      redirect_uri: callback_uri
    ), allow_other_host: true
  end

  def callback
    unless GoogleCalendar::Credentials.configured?
      redirect_to edit_profile_path, alert: "Google Calendar OAuth が未設定です。"
      return
    end

    if params[:state].blank? || params[:state] != session.delete(:google_calendar_oauth_state)
      redirect_to edit_profile_path, alert: "Google Calendar 連携に失敗しました（state が一致しません）。"
      return
    end

    if params[:error].present?
      redirect_to edit_profile_path, alert: "Google Calendar 連携がキャンセルされました。"
      return
    end

    client = GoogleCalendar::OAuth.exchange_code!(code: params[:code], redirect_uri: callback_uri)
    refresh_token = client.refresh_token
    if refresh_token.blank?
      redirect_to edit_profile_path, alert: "Google Calendar から refresh token を取得できませんでした。連携解除後、再度お試しください。"
      return
    end

    account = rodauth.rails_account
    account.connect_google_calendar!(refresh_token: refresh_token)
    GoogleCalendarSyncJob.perform_later(account.id)
    redirect_to edit_profile_path, notice: "Google Calendar と連携しました。予定の取り込みを開始します。"
  rescue Signet::AuthorizationError => e
    redirect_to edit_profile_path, alert: "Google Calendar 連携に失敗しました: #{e.message}"
  end

  def sync
    account = rodauth.rails_account
    unless account.google_calendar_connected?
      redirect_to edit_profile_path, alert: "Google Calendar が連携されていません。"
      return
    end

    GoogleCalendarSyncJob.perform_later(account.id)
    redirect_to edit_profile_path, notice: "Google Calendar の同期をキューに入れました。"
  end

  def disconnect
    account = rodauth.rails_account
    account.disconnect_google_calendar!
    redirect_to edit_profile_path, notice: "Google Calendar 連携を解除しました。"
  end

  private

  def callback_uri
    google_calendar_callback_url(host: request.host, port: callback_port, protocol: callback_protocol)
  end

  def callback_port
    return nil if request.standard_port?

    request.port
  end

  def callback_protocol
    request.ssl? ? "https" : "http"
  end
end
