// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import UserMenuController from "../user_menu_controller.js"

let application

beforeEach(() => {
  document.body.innerHTML = `
    <div data-controller="user-menu">
      <button type="button" data-user-menu-target="button" data-action="click->user-menu#toggle">Menu</button>
      <div class="hidden" data-user-menu-target="panel" role="menu">
        <a href="/profile" role="menuitem">Profile</a>
      </div>
    </div>
  `
  application = Application.start()
  application.register("user-menu", UserMenuController)
})

afterEach(() => {
  application?.stop()
  document.body.replaceChildren()
})

describe("user-menu", () => {
  it("opens its menu when the trigger is clicked", async () => {
    const button = document.querySelector("button")
    const panel = document.querySelector("[role='menu']")

    button.click()

    await vi.waitFor(() => expect(panel.classList.contains("hidden")).toBe(false))
    expect(button.getAttribute("aria-expanded")).toBe("true")
  })
})
