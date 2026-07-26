import { Controller } from "@hotwired/stimulus"

const MAX_VISIBLE_OPTIONS = 10

export default class extends Controller {
  static targets = ["form", "input", "hiddenInput", "options", "option"]

  connect() {
    this.activeIndex = -1
  }

  input() {
    this.syncHiddenInput()
    this.filterOptions()
  }

  prepareSubmit() {
    this.syncHiddenInput()
  }

  focus() {
    this.filterOptions()
  }

  select(event) {
    this.choose(event.currentTarget)
  }

  keepOpen(event) {
    event.preventDefault()
  }

  closeLater() {
    window.setTimeout(() => this.close(), 150)
  }

  keydown(event) {
    const options = this.visibleOptions

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      if (options.length === 0) return
      event.preventDefault()
      const change = event.key === "ArrowDown" ? 1 : -1
      this.setActive((this.activeIndex + change + options.length) % options.length)
      return
    }

    if (event.key === "Enter" && this.activeIndex >= 0) {
      event.preventDefault()
      this.choose(options[this.activeIndex])
    }
  }

  filterOptions() {
    const query = this.normalize(this.inputTarget.value)
    let visibleCount = 0

    this.optionTargets.forEach((option) => {
      const matches =
        query.length > 0 &&
        this.normalize(option.dataset.searchText).includes(query)
      const visible = matches && visibleCount < MAX_VISIBLE_OPTIONS
      option.classList.toggle("hidden", !visible)
      option.setAttribute("aria-selected", "false")
      if (visible) visibleCount += 1
    })

    this.optionsTarget.classList.toggle("hidden", visibleCount === 0)
    this.inputTarget.setAttribute("aria-expanded", visibleCount > 0 ? "true" : "false")
    this.setActive(-1)
  }

  choose(option) {
    this.inputTarget.value = option.dataset.directoryDisplayPath
    this.hiddenInputTarget.value = option.dataset.directoryPath
    this.close()
    this.formTarget.requestSubmit()
  }

  close() {
    this.optionsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.setActive(-1)
  }

  setActive(index) {
    let activeOption = null
    this.visibleOptions.forEach((option, optionIndex) => {
      const active = optionIndex === index
      option.classList.toggle("is-active", active)
      option.setAttribute("aria-selected", active ? "true" : "false")
      if (active) activeOption = option
    })
    if (activeOption?.id) {
      this.inputTarget.setAttribute("aria-activedescendant", activeOption.id)
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
    this.activeIndex = index
  }

  normalize(value) {
    return value.toString().trim().normalize("NFKC").toLocaleLowerCase()
  }

  syncHiddenInput() {
    const inputValue = this.normalize(this.inputTarget.value)
    const matchingOption = this.optionTargets.find(
      (option) => this.normalize(option.dataset.directoryDisplayPath) === inputValue
    )
    this.hiddenInputTarget.value = matchingOption?.dataset.directoryPath || this.inputTarget.value
  }

  get visibleOptions() {
    return this.optionTargets.filter((option) => !option.classList.contains("hidden"))
  }
}
