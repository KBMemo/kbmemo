/** Phase 6b: WYSIWYG-lite 拡張を Compartment でまとめる */
import { wysiwygLiteExtension } from "./wysiwyg_lite"
import { imageWysiwygExtension } from "./image_wysiwyg"
import { tableWysiwygFieldExtension } from "./table_wysiwyg_field"
import { wikiLinkWysiwygExtension } from "./wiki_link_wysiwyg"

export const WYSIWYG_PREF_STORAGE_KEY = "kbmemo_memo_editor_wysiwyg"

export function readWysiwygPreference() {
  try {
    return localStorage.getItem(WYSIWYG_PREF_STORAGE_KEY) !== "false"
  } catch {
    return true
  }
}

export function writeWysiwygPreference(enabled) {
  try {
    localStorage.setItem(WYSIWYG_PREF_STORAGE_KEY, enabled ? "true" : "false")
  } catch {
    /* ignore */
  }
}

export function wysiwygExtensionPack({ getMemoId, getWikiLabelsConfig }) {
  return [
    wysiwygLiteExtension(),
    imageWysiwygExtension(getMemoId),
    ...tableWysiwygFieldExtension(),
    ...wikiLinkWysiwygExtension(getWikiLabelsConfig)
  ]
}
