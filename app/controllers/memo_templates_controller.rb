# frozen_string_literal: true

class MemoTemplatesController < ApplicationController
  after_action :verify_authorized
  before_action :set_template, only: %i[edit update destroy]

  def index
    authorize MemoTemplate
    @memo_templates = policy_scope(MemoTemplate).order(:name)
  end

  def new
    @memo_template = MemoTemplate.new(account: rodauth.rails_account)
    authorize @memo_template
  end

  def create
    @memo_template = MemoTemplate.new(template_params.merge(account: rodauth.rails_account))
    authorize @memo_template

    if @memo_template.save
      redirect_to memo_templates_path, notice: "メモテンプレートを作成しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @memo_template
  end

  def update
    authorize @memo_template

    if @memo_template.update(template_params)
      redirect_to memo_templates_path, notice: "メモテンプレートを更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @memo_template
    @memo_template.destroy!
    redirect_to memo_templates_path, notice: "メモテンプレートを削除しました。", status: :see_other
  end

  private

  def set_template
    @memo_template = policy_scope(MemoTemplate).find(params[:id])
  end

  def template_params
    params.require(:memo_template).permit(:name, :title_template, :body_template, :tag_list)
  end
end
