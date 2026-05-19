# frozen_string_literal: true

class BoardColumnPolicy < ApplicationPolicy
  def update?
    BoardPolicy.new(user, record.board).update?
  end

  alias swap? update?
end
