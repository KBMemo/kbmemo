# frozen_string_literal: true

class ProfilesController < ApplicationController
  def edit
    prepare_profile_edit
  end

  def update
    @account = rodauth.rails_account
    if @account.update(profile_params)
      redirect_to edit_profile_path, notice: "プロフィールを保存しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def create_api_token
    @account = rodauth.rails_account
    @revealed_api_token = @account.generate_api_token!
    prepare_profile_edit
    flash.now[:notice] = "アカウント API トークンを発行しました。下の枠内に表示されます（再表示できません）。"
    render :edit
  end

  def destroy_api_token
    @account = rodauth.rails_account
    @account.revoke_api_token!
    redirect_to edit_profile_path, notice: "アカウント API トークンを無効化しました。"
  end

  def create_web_clip_token
    @account = rodauth.rails_account
    @revealed_web_clip_token = @account.generate_web_clip_token!
    prepare_profile_edit
    flash.now[:notice] = "Web クリップトークンを発行しました。下の枠内に表示されます（再表示できません）。"
    render :edit
  end

  def destroy_web_clip_token
    @account = rodauth.rails_account
    @account.revoke_web_clip_token!
    redirect_to edit_profile_path, notice: "Web クリップトークンを無効化しました。"
  end

  def create_tsuzura_api_token
    @account = rodauth.rails_account
    @revealed_tsuzura_api_token = @account.generate_tsuzura_api_token!
    prepare_profile_edit
    flash.now[:notice] = "Tsuzura CLI トークンを発行しました。下の枠内に表示されます（再表示できません）。"
    render :edit
  end

  def destroy_tsuzura_api_token
    @account = rodauth.rails_account
    @account.revoke_tsuzura_api_token!
    redirect_to edit_profile_path, notice: "Tsuzura CLI トークンを無効化しました。"
  end

  private

  def prepare_profile_edit
    @account ||= rodauth.rails_account
    @google_calendar_callback_url = google_calendar_callback_url(
      host: request.host,
      port: google_calendar_callback_port,
      protocol: google_calendar_callback_protocol
    )
    @google_calendar_synced_memos_count = google_calendar_synced_memos_count(@account)
  end

  def profile_params
    permitted = params.require(:account).permit(:nickname, :openai_api_key, :clear_openai_api_key)
    if ActiveModel::Type::Boolean.new.cast(permitted.delete(:clear_openai_api_key))
      permitted[:openai_api_key] = nil
    elsif permitted[:openai_api_key].blank?
      permitted.delete(:openai_api_key)
    end
    permitted
  end

  def google_calendar_callback_port
    return nil if request.standard_port?

    request.port
  end

  def google_calendar_callback_protocol
    request.ssl? ? "https" : "http"
  end

  def google_calendar_synced_memos_count(account)
    GoogleCalendar::Clear.new(account: account).synced_memos.count
  end
end
