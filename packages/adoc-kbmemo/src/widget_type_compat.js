export class KbmemoWidgetType {
  eq(_widget) {
    return false
  }

  updateDOM(_dom, _view, _from) {
    return false
  }

  compare(other) {
    return this === other || (this.constructor === other.constructor && this.eq(other))
  }

  get estimatedHeight() {
    return -1
  }

  get lineBreaks() {
    return 0
  }

  ignoreEvent(_event) {
    return true
  }

  destroy(_dom) {}
}
