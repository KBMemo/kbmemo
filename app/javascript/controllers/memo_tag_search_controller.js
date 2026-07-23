import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "input", "tagId", "clear", "options", "option"]

  connect() {
    this.activeIndex = -1
  }

  input() {
    this.tagIdTarget.value = ""
    this.clearTarget.classList.toggle("hidden", this.inputTarget.value.length === 0)
    this.filterOptions()
  }

  select(event) {
    this.choose(event.currentTarget)
  }

  keepOpen(event) {
    event.preventDefault()
  }

  closeLater() {
    setTimeout(() => this.close(), 150)
  }

  close() {
    this.optionsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.setActive(-1)
  }

  keydown(event) {
    const options = this.visibleOptions

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (options.length === 0) return
      const change = event.key === "ArrowDown" ? 1 : -1
      this.setActive((this.activeIndex + change + options.length) % options.length)
      return
    }

    if (event.key === "Enter" && this.activeIndex >= 0) {
      event.preventDefault()
      this.choose(options[this.activeIndex])
    }
  }

  submit(event) {
    if (this.inputTarget.value.length === 0 || this.tagIdTarget.value) return

    const matches = this.optionTargets.filter(
      (option) => this.normalize(option.dataset.tagName) === this.normalize(this.inputTarget.value)
    )
    if (matches.length === 1) {
      this.tagIdTarget.value = matches[0].dataset.tagId
      return
    }

    event.preventDefault()
    this.inputTarget.setCustomValidity("候補からタグを選択してください")
    this.inputTarget.reportValidity()
  }

  clear() {
    this.inputTarget.value = ""
    this.tagIdTarget.value = ""
    this.inputTarget.setCustomValidity("")
    this.close()
    this.formTarget.requestSubmit()
  }

  filterOptions() {
    this.inputTarget.setCustomValidity("")
    const query = this.normalize(this.inputTarget.value)
    let visibleCount = 0

    this.optionTargets.forEach((option) => {
      const visible = query.length > 0 && this.normalize(option.dataset.tagName).includes(query)
      option.classList.toggle("hidden", !visible)
      option.setAttribute("aria-selected", "false")
      if (visible) visibleCount += 1
    })

    this.optionsTarget.classList.toggle("hidden", visibleCount === 0)
    this.inputTarget.setAttribute("aria-expanded", visibleCount > 0 ? "true" : "false")
    this.setActive(-1)
  }

  choose(option) {
    this.inputTarget.value = option.dataset.tagName
    this.tagIdTarget.value = option.dataset.tagId
    this.inputTarget.setCustomValidity("")
    this.close()
    this.formTarget.requestSubmit()
  }

  setActive(index) {
    this.visibleOptions.forEach((option, optionIndex) => {
      option.classList.toggle("is-active", optionIndex === index)
      option.setAttribute("aria-selected", optionIndex === index ? "true" : "false")
    })
    this.activeIndex = index
  }

  get visibleOptions() {
    return this.optionTargets.filter((option) => !option.classList.contains("hidden"))
  }

  normalize(value) {
    return value.toString().trim().normalize("NFKC").toLocaleLowerCase()
  }
}
