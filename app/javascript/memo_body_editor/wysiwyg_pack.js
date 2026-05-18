/** Phase 6b: WYSIWYG-lite 拡張を Compartment でまとめる */
import { diagramWysiwygExtension } from "./diagram_wysiwyg"
import { mathWysiwygExtension } from "./math_wysiwyg"
import { wysiwygLiteExtension } from "./wysiwyg_lite"
import { imageWysiwygExtension } from "./image_wysiwyg"
import { tableWysiwygFieldExtension } from "./table_wysiwyg_field"
import { wikiLinkWysiwygExtension } from "./wiki_link_wysiwyg"
import { viewportLineRangeSyncExtension } from "./viewport_lazy"

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
    ...viewportLineRangeSyncExtension(),
    wysiwygLiteExtension(),
    diagramWysiwygExtension(getMemoId),
    mathWysiwygExtension(),
    imageWysiwygExtension(getMemoId),
    ...tableWysiwygFieldExtension(),
    ...wikiLinkWysiwygExtension(getWikiLabelsConfig)
  ]
}
