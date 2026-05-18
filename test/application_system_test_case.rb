# frozen_string_literal: true

require "test_helper"
require "capybara/cuprite"

# CI は常に headless。ローカルは既定でブラウザ表示（SSH 等は HEADLESS=1）。
def cuprite_headless?
  return true if ENV["CI"].present?
  return true if ENV["HEADLESS"].to_s.in?(%w[1 true yes])
  return false if ENV["HEADLESS"].to_s.in?(%w[0 false no])
  return false if ENV["SHOW_BROWSER"].to_s.in?(%w[1 true yes])

  false
end

Capybara.register_driver(:cuprite) do |app|
  browser_options = {}
  browser_options["no-sandbox"] = nil if ENV["CI"]

  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1400 ],
    browser_options: browser_options,
    headless: cuprite_headless?,
    inspector: ENV["CUPRITE_INSPECTOR"].present?
  )
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite, screen_size: [ 1400, 1400 ]

  # Browser + Git work tree do not mix well with multi-process system tests.
  parallelize(workers: 1)

  def sign_in_via_browser(fixture_key = :one)
    account = accounts(fixture_key)
    visit "/login"
    fill_in "login", with: account.email
    fill_in "password", with: "password"
    click_button type: "submit"
  end
end
