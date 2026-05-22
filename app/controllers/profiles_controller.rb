# frozen_string_literal: true

class ProfilesController < ApplicationController
  def edit
    @account = rodauth.rails_account
  end

  def update
    @account = rodauth.rails_account
    if @account.update(profile_params)
      redirect_to edit_profile_path, notice: "プロフィールを保存しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def create_clip_api_token
    @account = rodauth.rails_account
    token = @account.generate_clip_api_token!
    flash[:clip_api_token] = token
    redirect_to edit_profile_path, notice: "クリップ API トークンを発行しました。再表示できないので控えてください。"
  end

  def destroy_clip_api_token
    @account = rodauth.rails_account
    @account.revoke_clip_api_token!
    redirect_to edit_profile_path, notice: "クリップ API トークンを無効化しました。"
  end

  private

  def profile_params
    permitted = params.require(:account).permit(:nickname, :openai_api_key, :clear_openai_api_key)
    if ActiveModel::Type::Boolean.new.cast(permitted.delete(:clear_openai_api_key))
      permitted[:openai_api_key] = nil
    elsif permitted[:openai_api_key].blank?
      permitted.delete(:openai_api_key)
    end
    permitted
  end
end
