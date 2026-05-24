/** @type {WeakMap<HTMLElement, string>} */
const unitAdocSources = new WeakMap()

/**
 * @param {HTMLElement} unit
 * @param {string} adoc
 */
export function setUnitAdocSource(unit, adoc) {
  unitAdocSources.set(unit, adoc)
}

/**
 * @param {HTMLElement} unit
 */
export function getUnitAdocSource(unit) {
  return unitAdocSources.get(unit)
}

/**
 * @param {HTMLElement} unit
 */
export function hasUnitAdocSource(unit) {
  return unitAdocSources.has(unit)
}

/**
 * @param {HTMLElement} unit
 */
export function clearUnitAdocSource(unit) {
  unitAdocSources.delete(unit)
}

/**
 * @param {HTMLElement} from
 * @param {HTMLElement} to
 */
export function transferUnitAdocSource(from, to) {
  const adoc = unitAdocSources.get(from)
  if (adoc !== undefined) {
    unitAdocSources.set(to, adoc)
  }
  unitAdocSources.delete(from)
}
