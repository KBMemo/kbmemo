# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_templates
#
#  id             :bigint           not null, primary key
#  body_template  :text             default(""), not null
#  name           :string           not null
#  tag_list       :text             default(""), not null
#  title_template :string           default(""), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_memo_templates_on_account_id           (account_id)
#  index_memo_templates_on_account_id_and_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class MemoTemplate < ApplicationRecord
  belongs_to :account

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :account_id }
  validates :title_template, length: { maximum: 500 }

  before_validation :normalize_fields

  private

  def normalize_fields
    self.name = name.to_s.strip
    self.title_template = title_template.to_s
    self.body_template = body_template.to_s
    self.tag_list = tag_list.to_s
  end
end
