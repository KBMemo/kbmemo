import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    createUrl: String,
    memoDirectoryId: Number
  }

  async create(event) {
    const button = event.currentTarget
    const title = button.dataset.wikiTitle?.trim()
    if (!title || button.disabled) return

    button.disabled = true
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")

    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "application/json"
        },
        body: JSON.stringify({
          memo: {
            body: `= ${title}\n\n`,
            memo_directory_id: this.memoDirectoryIdValue,
            slug: "",
            slug_manual: false,
            title_manual: false,
            tag_list: "",
            properties_yaml: "{}"
          }
        })
      })

      if (res.status === 201) {
        const data = await res.json()
        const navigate = window.Turbo?.visit ?? ((url) => window.location.assign(url))
        navigate(data.edit_path)
        return
      }

      if (res.status === 422) {
        const err = await res.json().catch(() => ({}))
        const message =
          Array.isArray(err.errors) && err.errors.length > 0
            ? err.errors.join("\n")
            : "メモを作成できませんでした"
        window.alert(message)
      }
    } catch (error) {
      console.error(error)
      window.alert("メモを作成できませんでした")
    } finally {
      button.disabled = false
    }
  }
}
