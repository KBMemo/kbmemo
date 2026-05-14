# frozen_string_literal: true

require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "display_name uses nickname when present" do
    a = accounts(:one)
    assert_equal "Freddie", a.display_name
  end

  test "display_name falls back to email when nickname blank" do
    a = accounts(:two)
    assert_equal "brian@queen.com", a.display_name
  end

  test "nickname is stripped and blank becomes nil" do
    a = accounts(:two)
    a.update!(nickname: "  Brian  ")
    assert_equal "Brian", a.nickname
    a.update!(nickname: "   ")
    assert_nil a.nickname
  end

  test "nickname length validation" do
    a = accounts(:two)
    a.nickname = "x" * 41
    assert_not a.valid?
    assert_includes a.errors[:nickname], "is too long (maximum is 40 characters)"
  end
end
