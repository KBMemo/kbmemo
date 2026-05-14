# frozen_string_literal: true

class ProfilesController < ApplicationController
  def edit
    @account = rodauth.rails_account
  end

  def update
    @account = rodauth.rails_account
    if @account.update(profile_params)
      redirect_to edit_profile_path, notice: "ニックネームを保存しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:account).permit(:nickname)
  end
end
