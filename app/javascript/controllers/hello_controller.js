import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.debug("[stimulus] hello_controller connected")
  }
}
