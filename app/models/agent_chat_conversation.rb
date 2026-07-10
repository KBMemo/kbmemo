# frozen_string_literal: true

# == Schema Information
#
# Table name: agent_chat_conversations
#
#  id         :bigint           not null, primary key
#  title      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  memo_id    :bigint
#
# Indexes
#
#  index_agent_chat_conversations_on_account_id                 (account_id)
#  index_agent_chat_conversations_on_account_id_and_updated_at  (account_id,updated_at)
#  index_agent_chat_conversations_on_memo_id                    (memo_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (memo_id => memos.id)
#
class AgentChatConversation < ApplicationRecord
  TITLE_MAX_LENGTH = 80

  belongs_to :account
  belongs_to :memo, optional: true

  has_many :messages,
           class_name: "AgentChatMessage",
           foreign_key: :agent_chat_conversation_id,
           inverse_of: :conversation,
           dependent: :destroy

  validates :title, length: { maximum: TITLE_MAX_LENGTH }, allow_blank: true

  def assign_title_from!(text)
    return if title.present?

    snippet = text.to_s.strip.gsub(/\s+/, " ")
    return if snippet.blank?

    update!(title: snippet.truncate(TITLE_MAX_LENGTH, omission: "…"))
  end
end
