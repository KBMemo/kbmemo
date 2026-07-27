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
  if ENV["CI"]
    browser_options["no-sandbox"] = nil
    browser_options["disable-dev-shm-usage"] = nil
  end
  browser_path = ENV["CUPRITE_BROWSER_PATH"].presence
  process_timeout = ENV.fetch("CUPRITE_PROCESS_TIMEOUT", "10").to_i

  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1400 ],
    browser_path: browser_path,
    browser_options: browser_options,
    headless: cuprite_headless?,
    inspector: ENV["CUPRITE_INSPECTOR"].present?,
    process_timeout: process_timeout
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
