# frozen_string_literal: true

class MemoMetadataSuggestionsController < ApplicationController
  after_action :verify_authorized

  def create
    memo = policy_scope(Memo).find(params[:id])
    authorize memo, :suggest_metadata?

    result = MemoMetadataSuggester.new(
      account: rodauth.rails_account,
      title: params[:title],
      body: params[:body],
      current_tags: params[:tags],
      existing_tags: existing_tag_names
    ).call

    render json: result
  rescue Chat::LlmClient::ConnectionError => e
    render json: { error: e.message, settings_url: chat_server_path }, status: :unprocessable_entity
  rescue Chat::LlmClient::Error, KeyError, ArgumentError => e
    render json: { error: e.message, settings_url: chat_server_path }, status: :unprocessable_entity
  end

  private

  def existing_tag_names
    Tag.left_joins(:memo_tags)
      .group(:id)
      .order(Arel.sql("COUNT(memo_tags.id) DESC"), :name)
      .limit(MemoMetadataSuggester::MAX_EXISTING_TAGS)
      .pluck(:name)
  end
end
