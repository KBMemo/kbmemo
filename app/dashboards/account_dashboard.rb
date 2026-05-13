# frozen_string_literal: true

require "administrate/base_dashboard"

class AccountDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    email: Field::String,
    status: Field::Select.with_options(
      searchable: false,
      collection: ->(_field) { Account.statuses.keys }
    ),
    admin: Field::Boolean
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    email
    status
    admin
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    email
    status
    admin
  ].freeze

  FORM_ATTRIBUTES = %i[
    email
    status
    admin
  ].freeze

  COLLECTION_FILTERS = {}.freeze
end
