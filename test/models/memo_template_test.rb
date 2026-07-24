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
require "test_helper"

class MemoTemplateTest < ActiveSupport::TestCase
  test "requires a unique name within an account" do
    duplicate = accounts(:one).memo_templates.new(name: memo_templates(:daily).name)

    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  test "allows the same name for another account" do
    template = accounts(:two).memo_templates.new(name: memo_templates(:daily).name)

    assert template.valid?
  end
end
